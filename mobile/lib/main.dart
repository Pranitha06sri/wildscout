import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'services/analysis_service.dart';

void main() {
  const sample = bool.fromEnvironment('USE_SAMPLE_DATA', defaultValue: true);
  const configured = String.fromEnvironment('API_BASE_URL');
  final baseUrl = configured.isNotEmpty
      ? configured
      : (defaultTargetPlatform == TargetPlatform.android
            ? 'http://10.0.2.2:8000'
            : 'http://127.0.0.1:8000');
  runApp(
    WildScoutApp(
      sampleMode: sample,
      service: sample
          ? SampleAnalysisService()
          : LocalAnalysisService(baseUrl: baseUrl),
    ),
  );
}
