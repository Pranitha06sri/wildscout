import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wildscout/app.dart';
import 'package:wildscout/domain/analysis_result.dart';
import 'package:wildscout/services/analysis_service.dart';
import 'package:wildscout/services/photo_capture.dart';

class TestService implements AnalysisService {
  final pending = Completer<AnalysisResult>();
  int calls = 0;
  bool cancelled = false;
  @override
  Future<AnalysisResult> analyze(XFile? image) {
    calls++;
    return pending.future;
  }

  @override
  void cancel() {
    cancelled = true;
  }
}

class TestCapture implements PhotoCapture {
  ImageSource? source;
  bool denied = false;
  @override
  Future<XFile?> recover() async => null;
  @override
  Future<XFile?> pick(ImageSource value) async {
    source = value;
    if (denied) throw PlatformException(code: 'camera_access_denied');
    return XFile.fromData(
      File('assets/fern.jpg').readAsBytesSync(),
      path: 'leaf.jpg',
    );
  }
}

void main() {
  final data = decodeAnalysis(
    File('assets/sample_analyze_response.json').readAsStringSync(),
  );
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final pair in [('Inter', 'Inter.ttf'), ('Jakarta', 'Jakarta.ttf')]) {
      await (FontLoader(
        pair.$1,
      )..addFont(rootBundle.load('assets/${pair.$2}'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> screen(
    WidgetTester tester,
    String name, {
    bool capture = false,
  }) async {
    expect(find.byKey(ValueKey('screen-$name')), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (capture && const bool.fromEnvironment('CAPTURE_SCREENSHOTS')) {
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('artifacts/$name.png'),
      );
    }
  }

  testWidgets(
    'navigates all eight screens with fixture content and image preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = TestService();
      final capture = TestCapture();
      await tester.pumpWidget(WildScoutApp(service: service, capture: capture));
      await screen(tester, 'home', capture: true);
      await tap(tester, 'Scout something unfamiliar');
      await screen(tester, 'camera', capture: true);
      await tap(tester, 'Take a photo');
      await tester.pumpAndSettle();
      expect(capture.source, ImageSource.camera);
      expect(find.text('Your photo is ready to preview.'), findsOneWidget);
      await tap(tester, 'Explore sample field note');
      await screen(tester, 'analyzing', capture: true);
      service.pending.complete(data);
      await tester.pumpAndSettle();
      await screen(tester, 'identification', capture: true);
      expect(find.text(data.identification), findsOneWidget);
      expect(find.text(data.visualClues.first), findsOneWidget);
      await tap(tester, 'Check WildSafe');
      await screen(tester, 'wildSafe', capture: true);
      expect(find.text(data.safetyNote), findsOneWidget);
      await tap(tester, 'Learn nature context');
      await screen(tester, 'context', capture: true);
      expect(find.text(data.natureContext), findsOneWidget);
      await tap(tester, 'Give me a mission');
      await screen(tester, 'mission', capture: true);
      expect(find.text(data.mission), findsOneWidget);
      await tap(tester, 'Got it — I’m looking');
      await screen(tester, 'phoneDown', capture: true);
      await tap(tester, 'Scout again');
      await tester.pumpAndSettle();
      await screen(tester, 'home');
      expect(service.calls, 1);
    },
  );
  testWidgets('cancel ignores stale analysis results', (tester) async {
    final service = TestService();
    await tester.pumpWidget(
      WildScoutApp(service: service, capture: TestCapture()),
    );
    await tap(tester, 'Scout something unfamiliar');
    await tap(tester, 'Explore sample field note');
    await tap(tester, 'Cancel analysis');
    expect(service.cancelled, isTrue);
    service.pending.complete(data);
    await tester.pumpAndSettle();
    await screen(tester, 'camera');
  });
  testWidgets('shows actionable permission and API errors', (tester) async {
    final service = TestService();
    await tester.pumpWidget(
      WildScoutApp(service: service, capture: TestCapture()..denied = true),
    );
    await tap(tester, 'Scout something unfamiliar');
    await tap(tester, 'Take a photo');
    await tester.pumpAndSettle();
    expect(find.textContaining('Check app permissions'), findsOneWidget);
    await tap(tester, 'Explore sample field note');
    service.pending.completeError(
      const AnalysisFailure('Local backend is offline.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Local backend is offline.'), findsOneWidget);
    await screen(tester, 'camera');
  });
  testWidgets('large text and narrow display remain scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: ScoutFlow(
            service: TestService(),
            capture: TestCapture(),
            sampleMode: true,
          ),
        ),
      ),
    );
    await tap(tester, 'Scout something unfamiliar');
    await screen(tester, 'camera');
  });
}
