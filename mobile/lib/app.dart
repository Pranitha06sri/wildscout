import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'domain/analysis_result.dart';
import 'services/analysis_service.dart';
import 'services/photo_capture.dart';

const evergreen = Color(0xFF1B3B2B);
const moss = Color(0xFF376847);
const parchment = Color(0xFFF6FBF4);
const sage = Color(0xFFE5E9E3);
const bark = Color(0xFF753400);

enum ScoutScreen {
  home,
  camera,
  analyzing,
  identification,
  wildSafe,
  context,
  mission,
  phoneDown,
}

class WildScoutApp extends StatelessWidget {
  const WildScoutApp({
    super.key,
    required this.service,
    this.sampleMode = true,
    this.capture,
  });
  final AnalysisService service;
  final bool sampleMode;
  final PhotoCapture? capture;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WildScout',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: parchment,
      colorScheme: ColorScheme.fromSeed(
        seedColor: evergreen,
        primary: evergreen,
        secondary: moss,
        surface: parchment,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'Jakarta',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.2,
          color: evergreen,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Jakarta',
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.25,
          color: evergreen,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Jakarta',
          fontSize: 21,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: evergreen,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          height: 1.55,
          color: Color(0xFF181D19),
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: Color(0xFF424843),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'Jakarta',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
    ),
    home: ScoutFlow(
      service: service,
      sampleMode: sampleMode,
      capture: capture ?? DevicePhotoCapture(),
    ),
  );
}

class ScoutFlow extends StatefulWidget {
  const ScoutFlow({
    super.key,
    required this.service,
    required this.capture,
    required this.sampleMode,
  });
  final AnalysisService service;
  final PhotoCapture capture;
  final bool sampleMode;
  @override
  State<ScoutFlow> createState() => _ScoutFlowState();
}

class _ScoutFlowState extends State<ScoutFlow> {
  ScoutScreen screen = ScoutScreen.home;
  XFile? photo;
  Uint8List? preview;
  AnalysisResult? result;
  String? error;
  bool picking = false;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    _recoverPhoto();
  }

  Future<void> _recoverPhoto() async {
    try {
      final recovered = await widget.capture.recover();
      if (recovered != null &&
          mounted &&
          photo == null &&
          screen == ScoutScreen.home) {
        final bytes = await recovered.readAsBytes();
        if (!mounted || screen != ScoutScreen.home) return;
        setState(() {
          photo = recovered;
          preview = bytes;
          screen = ScoutScreen.camera;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Your previous photo could not be recovered. Please capture it again.';
        });
      }
    }
  }

  @override
  void dispose() {
    requestId++;
    widget.service.cancel();
    super.dispose();
  }

  void go(ScoutScreen next) => setState(() {
    screen = next;
    error = null;
  });
  void back() {
    requestId++;
    widget.service.cancel();
    go(switch (screen) {
      ScoutScreen.home || ScoutScreen.camera => ScoutScreen.home,
      ScoutScreen.analyzing || ScoutScreen.identification => ScoutScreen.camera,
      ScoutScreen.wildSafe => ScoutScreen.identification,
      ScoutScreen.context => ScoutScreen.wildSafe,
      ScoutScreen.mission => ScoutScreen.context,
      ScoutScreen.phoneDown => ScoutScreen.mission,
    });
  }

  void restart() {
    requestId++;
    widget.service.cancel();
    setState(() {
      screen = ScoutScreen.home;
      result = null;
      photo = null;
      preview = null;
      error = null;
    });
  }

  Future<void> pick(ImageSource source) async {
    if (picking) {
      return;
    }
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final selected = await widget.capture.pick(source);
      if (selected == null) return;
      if (await selected.length() > 8 * 1024 * 1024) {
        throw const AnalysisFailure(
          'This photo is too large. Choose an image smaller than 8 MiB.',
        );
      }
      final bytes = await selected.readAsBytes();
      if (!mounted || screen != ScoutScreen.camera) return;
      setState(() {
        photo = selected;
        preview = bytes;
        result = null;
      });
    } on AnalysisFailure catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Camera or photos access is unavailable. Check app permissions, or choose another image.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          picking = false;
        });
      }
    }
  }

  Future<void> analyze() async {
    if (screen == ScoutScreen.analyzing || picking) return;
    final current = ++requestId;
    setState(() {
      screen = ScoutScreen.analyzing;
      result = null;
      error = null;
    });
    try {
      final value = await widget.service.analyze(photo);
      if (!mounted || current != requestId) return;
      setState(() {
        result = value;
        screen = ScoutScreen.identification;
      });
    } catch (failure) {
      if (!mounted || current != requestId) return;
      setState(() {
        screen = ScoutScreen.camera;
        error = failure is AnalysisFailure
            ? failure.message
            : 'This analysis could not be completed. Please try again.';
      });
    }
  }

  Widget heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 10),
      Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 24),
    ],
  );

  Widget action(
    String label,
    VoidCallback? callback, {
    IconData icon = Icons.arrow_forward_rounded,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: FilledButton.icon(
      onPressed: callback,
      icon: Icon(icon),
      label: Text(label),
    ),
  );

  Widget photograph({
    String asset = 'assets/fern.jpg',
    double height = 230,
    bool captured = false,
  }) {
    final child = captured && preview != null
        ? Image.memory(
            preview!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.broken_image_outlined, size: 60),
            ),
          )
        : Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(
              child: Icon(Icons.forest_outlined, size: 96, color: moss),
            ),
          );
    return Semantics(
      label: captured && preview != null
          ? 'Selected image preview'
          : 'Decorative forest illustration',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(width: double.infinity, height: height, child: child),
      ),
    );
  }

  List<Widget> content() {
    final data = result;
    switch (screen) {
      case ScoutScreen.home:
        return [
          const _Badge(
            'LOCAL AI · NO CLOUD PROCESSING',
            icon: Icons.eco_outlined,
          ),
          const SizedBox(height: 28),
          heading(
            'Look closer.',
            'Step outside. Notice what catches your eye. Then put the screen away.',
          ),
          Stack(
            alignment: Alignment.bottomLeft,
            children: [
              photograph(asset: 'assets/forest.jpg', height: 240),
              Container(
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xBB032517)],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A MOMENT OUTSIDE',
                      style: TextStyle(color: Colors.white, letterSpacing: 1.2),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'A little curiosity.\nA little more nature.',
                      style: TextStyle(
                        fontFamily: 'Jakarta',
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action(
            'Scout something unfamiliar',
            () => go(ScoutScreen.camera),
            icon: Icons.photo_camera_outlined,
          ),
          const SizedBox(height: 24),
          const _FieldCard(
            icon: Icons.shield_outlined,
            title: 'Observe from a distance',
            body:
                'An image cannot establish safety. Never eat, touch or approach unfamiliar plants, fungi or animals.',
          ),
          const SizedBox(height: 24),
          const Text(
            '“Designed to help you look up, not down.”',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontStyle: FontStyle.italic,
              color: moss,
            ),
          ),
        ];
      case ScoutScreen.camera:
        return [
          heading(
            'Scout Camera',
            'Frame what caught your eye. Keep your distance and stay on a safe path.',
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              photograph(height: 320, captured: true),
              if (preview == null)
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFB6EDC2),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.photo_camera_outlined,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            preview == null
                ? 'Open the camera to capture your own image.'
                : 'Your photo is ready to preview.',
            textAlign: TextAlign.center,
          ),
          action(
            preview == null ? 'Take a photo' : 'Retake photo',
            picking ? null : () => pick(ImageSource.camera),
            icon: Icons.camera_alt_outlined,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: picking ? null : () => pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from photos'),
          ),
          if (picking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (widget.sampleMode)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text(
                'Sample preview: the next screens use an example field note. Your photo is not analyzed.',
              ),
            ),
          action(
            widget.sampleMode ? 'Explore sample field note' : 'Analyze photo',
            picking || (!widget.sampleMode && photo == null) ? null : analyze,
            icon: Icons.search_rounded,
          ),
        ];
      case ScoutScreen.analyzing:
        return [
          photograph(captured: true, height: 300),
          const SizedBox(height: 32),
          const Center(child: CircularProgressIndicator(color: moss)),
          const SizedBox(height: 28),
          heading(
            'Taking a closer look…',
            widget.sampleMode
                ? 'Loading your sample field note.'
                : 'Your photo is being analyzed by the local AI. This can take several minutes.',
          ),
          const _FieldCard(
            icon: Icons.nature_people_outlined,
            title: 'Field presence',
            body:
                'Take a breath. Notice the canopy around you while you wait. Stay in your existing safe position.',
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: back, child: const Text('Cancel analysis')),
        ];
      case ScoutScreen.identification:
        return [
          heading(
            'Identification',
            'A visual suggestion, not a confirmed identification.',
          ),
          _Badge(
            '${data!.confidence.name.toUpperCase()} VISUAL CONFIDENCE',
            icon: Icons.visibility_outlined,
          ),
          const SizedBox(height: 16),
          photograph(captured: !widget.sampleMode),
          const SizedBox(height: 20),
          _FieldCard(
            icon: Icons.eco_outlined,
            title: data.identification,
            body:
                'Verify with an independent expert before making decisions about wildlife.',
          ),
          const SizedBox(height: 24),
          Text(
            'Key visual clues',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...data.visualClues.map(
            (clue) => Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _FieldCard(icon: Icons.check_outlined, body: clue),
            ),
          ),
          action(
            'Check WildSafe',
            () => go(ScoutScreen.wildSafe),
            icon: Icons.shield_outlined,
          ),
        ];
      case ScoutScreen.wildSafe:
        final level = data!.safetyLevel;
        final label = switch (level) {
          SafetyLevel.high => 'HIGH · KEEP YOUR DISTANCE',
          SafetyLevel.unknown => 'UNKNOWN · STAY CAUTIOUS',
          SafetyLevel.low || SafetyLevel.caution => 'CAUTION · OBSERVE ONLY',
        };
        return [
          heading('WildSafe', 'A conservative field check.'),
          _Badge(label, icon: Icons.warning_amber_rounded, warning: true),
          const SizedBox(height: 20),
          _FieldCard(
            icon: Icons.shield_outlined,
            title: 'Safety cannot be established from a photo',
            body: data.safetyNote,
            warning: true,
          ),
          const SizedBox(height: 16),
          const _FieldCard(
            icon: Icons.pan_tool_outlined,
            title: 'Leave it as you found it',
            body:
                'Do not eat, touch, handle or approach unfamiliar organisms. Observe from an existing safe position.',
          ),
          action(
            'Learn nature context',
            () => go(ScoutScreen.context),
            icon: Icons.menu_book_outlined,
          ),
        ];
      case ScoutScreen.context:
        return [
          heading(
            'Quick Nature Context',
            'One small field note. Then eyes up.',
          ),
          photograph(captured: !widget.sampleMode),
          const SizedBox(height: 20),
          _FieldCard(
            icon: Icons.forest_outlined,
            title: 'The nature around you',
            body: data!.natureContext,
          ),
          const SizedBox(height: 16),
          const Text(
            'AI context is unverified and may be inaccurate. Treat it as a starting point for learning.',
          ),
          action(
            'Give me a mission',
            () => go(ScoutScreen.mission),
            icon: Icons.spa_outlined,
          ),
        ];
      case ScoutScreen.mission:
        return [
          heading(
            'Touch Grass Mission',
            'A deliberate step away from the screen. Tune your eyes to the world around you.',
          ),
          photograph(asset: 'assets/forest.jpg', height: 190),
          const SizedBox(height: 24),
          _FieldCard(
            icon: Icons.nature_people_outlined,
            title: 'Your observation',
            body: data!.mission,
          ),
          const SizedBox(height: 16),
          const _FieldCard(
            icon: Icons.shield_outlined,
            title: 'Stay where it is safe',
            body:
                'No collecting or handling wildlife. No need to leave your existing safe position.',
          ),
          action(
            'Got it — I’m looking',
            () => go(ScoutScreen.phoneDown),
            icon: Icons.phone_android_outlined,
          ),
        ];
      case ScoutScreen.phoneDown:
        return [
          const SizedBox(height: 36),
          const Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: sage,
              child: Icon(Icons.eco_outlined, color: moss, size: 42),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'You’ve got what you need.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          const Text(
            'Put your phone away and explore.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: moss,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          _FieldCard(body: data!.mission),
          const SizedBox(height: 24),
          photograph(asset: 'assets/forest.jpg', height: 160),
          const SizedBox(height: 24),
          const Text(
            'Press your phone’s power button to turn off the screen. WildScout will be here when you return.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: restart,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Scout again'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: screen == ScoutScreen.home,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      if (screen != ScoutScreen.home)
                        IconButton(
                          onPressed: back,
                          tooltip: 'Go back',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      else
                        const SizedBox(width: 16),
                      const Icon(Icons.eco_outlined, color: evergreen),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'WildScout',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Jakarta',
                            fontWeight: FontWeight.w700,
                            fontSize: 21,
                            color: evergreen,
                          ),
                        ),
                      ),
                      if (widget.sampleMode)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Text(
                            'SAMPLE',
                            style: TextStyle(
                              color: moss,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('screen-${screen.name}'),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Semantics(
                              liveRegion: true,
                              child: _FieldCard(
                                icon: Icons.error_outline,
                                title: 'Let’s try again',
                                body: error!,
                                warning: true,
                              ),
                            ),
                          ),
                        ...content(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.icon, this.warning = false});
  final String text;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFDBC9) : sage,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: warning ? bark : moss),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: warning ? bark : moss,
                letterSpacing: .5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    this.icon,
    this.title,
    required this.body,
    this.warning = false,
  });
  final IconData? icon;
  final String? title;
  final String body;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFE9DD) : Colors.white,
      border: Border.all(
        color: warning ? const Color(0xFFE6BA9E) : const Color(0xFFE2E0D8),
      ),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null || title != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(icon, color: warning ? bark : moss),
                ),
              if (title != null)
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
        if (title != null) const SizedBox(height: 12),
        Text(body, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
