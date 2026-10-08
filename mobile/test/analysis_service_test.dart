import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wildscout/domain/analysis_result.dart';
import 'package:wildscout/services/analysis_service.dart';

void main() {
  final fixture = File(
    'assets/sample_analyze_response.json',
  ).readAsStringSync();
  final image = XFile.fromData(
    Uint8List.fromList([1, 2, 3]),
    path: 'nature.png',
  );
  test(
    'bundled fixture equals canonical backend sample and decodes every field',
    () {
      expect(
        jsonDecode(fixture),
        jsonDecode(
          File('../docs/sample_analyze_response.json').readAsStringSync(),
        ),
      );
      final result = decodeAnalysis(fixture);
      expect(result.confidence, Confidence.moderate);
      expect(result.safetyLevel, SafetyLevel.caution);
      expect(result.visualClues, [
        'Green oval leaves',
        'Visible branching veins',
      ]);
      expect(result.mission, contains('Put your phone away'));
    },
  );
  test(
    'reject malformed JSON, missing fields, invalid enums and invalid lists',
    () {
      for (final value in [
        '{}',
        '[]',
        'not json',
        jsonEncode({
          ...jsonDecode(fixture) as Map<String, dynamic>,
          'confidence': 'certain',
        }),
        jsonEncode({
          ...jsonDecode(fixture) as Map<String, dynamic>,
          'visual_clues': [42],
        }),
      ]) {
        expect(() => decodeAnalysis(value), throwsFormatException);
      }
    },
  );
  test(
    'sends multipart image field to configurable analyze endpoint',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(fixture, 200);
      });
      final result = await LocalAnalysisService(
        baseUrl: 'http://10.0.2.2:8000/',
        clientFactory: () => client,
      ).analyze(image);
      expect(captured!.method, 'POST');
      expect(captured!.url.toString(), 'http://10.0.2.2:8000/analyze');
      expect(
        captured!.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(
        utf8.decode(captured!.bodyBytes, allowMalformed: true),
        contains('name="image"; filename="nature.png"'),
      );
      expect(result.natureContext, contains('leafy vegetation'));
    },
  );
  for (final code in [400, 413, 415, 422, 502, 503, 504, 500]) {
    test('handles HTTP $code without treating errors as analysis', () async {
      final service = LocalAnalysisService(
        baseUrl: 'http://localhost:8000',
        clientFactory: () =>
            MockClient((_) async => http.Response('{"detail":"error"}', code)),
      );
      await expectLater(
        service.analyze(image),
        throwsA(isA<AnalysisFailure>()),
      );
    });
  }
  test(
    'decodes UTF-8 nature context without depending on response charset',
    () async {
      final json = jsonDecode(fixture) as Map<String, dynamic>;
      json['nature_context'] = 'Unverified model context: forêt 🌿';
      final service = LocalAnalysisService(
        baseUrl: 'http://localhost:8000',
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes(utf8.encode(jsonEncode(json)), 200),
        ),
      );
      expect(
        (await service.analyze(image)).natureContext,
        json['nature_context'],
      );
    },
  );
  test('rejects schema-invalid HTTP 200 and handles timeout', () async {
    final invalid = LocalAnalysisService(
      baseUrl: 'http://localhost:8000',
      clientFactory: () => MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(invalid.analyze(image), throwsA(isA<AnalysisFailure>()));
    final slow = LocalAnalysisService(
      baseUrl: 'http://localhost:8000',
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(slow.analyze(image), throwsA(isA<AnalysisFailure>()));
  });
}
