import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../domain/analysis_result.dart';

abstract class AnalysisService {
  Future<AnalysisResult> analyze(XFile? image);
  void cancel();
}

class AnalysisFailure implements Exception {
  const AnalysisFailure(this.message);
  final String message;
}

AnalysisResult decodeAnalysis(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Expected analysis object');
  }
  return AnalysisResult.fromJson(json);
}

class SampleAnalysisService implements AnalysisService {
  @override
  Future<AnalysisResult> analyze(XFile? image) async {
    final data = await rootBundle.loadString(
      'assets/sample_analyze_response.json',
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return decodeAnalysis(data);
  }

  @override
  void cancel() {}
}

class LocalAnalysisService implements AnalysisService {
  LocalAnalysisService({
    required String baseUrl,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 660),
  }) : endpoint = Uri.parse(
         '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/analyze',
       ),
       _clientFactory = clientFactory ?? http.Client.new {
    if (endpoint.scheme != 'http' ||
        endpoint.host.isEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.userInfo.isNotEmpty) {
      throw const FormatException('Use a local http API base URL');
    }
  }
  final Uri endpoint;
  final Duration timeout;
  final http.Client Function() _clientFactory;
  http.Client? _pending;
  @override
  Future<AnalysisResult> analyze(XFile? image) async {
    if (image == null) throw const AnalysisFailure('Choose a photo first.');
    final client = _clientFactory();
    _pending = client;
    try {
      return await (() async {
        final bytes = await image.readAsBytes();
        if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
          throw const AnalysisFailure('Choose an image smaller than 8 MiB.');
        }
        final request = http.MultipartRequest('POST', endpoint)
          ..files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: image.name),
          );
        final response = await http.Response.fromStream(
          await client.send(request),
        );
        if (response.statusCode != 200) {
          throw AnalysisFailure(switch (response.statusCode) {
            400 || 415 || 422 =>
              'This image could not be read. Choose a JPEG, PNG or WebP photo.',
            413 =>
              'This photo is too large. Choose one smaller than 8 MiB and 20 megapixels.',
            502 => 'The analysis was incomplete. Please try again.',
            503 =>
              'The local AI is unavailable. Check that Ollama and the backend are running.',
            504 => 'The local AI took too long. Please try again.',
            _ => 'The analysis could not be completed. Please try again.',
          });
        }
        return decodeAnalysis(utf8.decode(response.bodyBytes));
      })().timeout(timeout);
    } on AnalysisFailure {
      rethrow;
    } on TimeoutException {
      throw const AnalysisFailure(
        'The local AI took too long. Please try again.',
      );
    } on FormatException {
      throw const AnalysisFailure(
        'The analysis response was invalid. Please try again.',
      );
    } catch (_) {
      throw const AnalysisFailure(
        'Cannot reach the local backend. Check your connection and try again.',
      );
    } finally {
      client.close();
      if (identical(_pending, client)) _pending = null;
    }
  }

  @override
  void cancel() {
    _pending?.close();
    _pending = null;
  }
}
