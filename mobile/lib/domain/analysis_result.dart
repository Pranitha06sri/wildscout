enum Confidence { low, moderate, high }

enum SafetyLevel { unknown, low, caution, high }

class AnalysisResult {
  const AnalysisResult({
    required this.identification,
    required this.confidence,
    required this.visualClues,
    required this.natureContext,
    required this.safetyLevel,
    required this.safetyNote,
    required this.mission,
  });
  final String identification;
  final Confidence confidence;
  final List<String> visualClues;
  final String natureContext;
  final SafetyLevel safetyLevel;
  final String safetyNote;
  final String mission;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    const keys = {
      'identification',
      'confidence',
      'visual_clues',
      'nature_context',
      'safety_level',
      'safety_note',
      'mission',
    };
    if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
      throw const FormatException('Unexpected analysis fields');
    }
    String text(String key, int max) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty || value.length > max) {
        throw FormatException('Invalid $key');
      }
      return value.trim();
    }

    final rawClues = json['visual_clues'];
    if (rawClues is! List ||
        rawClues.isEmpty ||
        rawClues.length > 8 ||
        rawClues.any(
          (v) => v is! String || v.trim().isEmpty || v.length > 300,
        )) {
      throw const FormatException('Invalid visual clues');
    }
    final confidence = text('confidence', 8);
    final safety = text('safety_level', 7);
    if (!Confidence.values.any((v) => v.name == confidence) ||
        !SafetyLevel.values.any((v) => v.name == safety)) {
      throw const FormatException('Invalid analysis category');
    }
    return AnalysisResult(
      identification: text('identification', 500),
      confidence: Confidence.values.byName(confidence),
      visualClues: List.unmodifiable(
        rawClues.cast<String>().map((v) => v.trim()),
      ),
      natureContext: text('nature_context', 1000),
      safetyLevel: SafetyLevel.values.byName(safety),
      safetyNote: text('safety_note', 1000),
      mission: text('mission', 500),
    );
  }
}
