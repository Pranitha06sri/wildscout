# WildScout mobile

Flutter companion for the existing local FastAPI backend. Eight screens:
Home/Scout → Scout Camera → Analyzing → Identification → WildSafe →
Quick Nature Context → Touch Grass Mission → Phone-Down.

## Run the sample flow

```powershell
cd mobile
flutter pub get
flutter run
```

Sample mode is **on by default**. No backend or Ollama request is made. The app
bundles a copy of `../docs/sample_analyze_response.json`; tests check that the copy
matches the canonical backend fixture. The camera and image-library buttons use
the native platform picker. Captured photos can be previewed, but sample mode
explicitly says that the displayed identification is an example and does not
analyze the photo. This lets development exercise all screens without a four-minute
inference. No photographs are persisted by this app, indexed or sent to a cloud.

## Connect to FastAPI

Start the existing Ollama and FastAPI services as documented in the root README.
For an Android emulator:

```powershell
flutter run --dart-define=USE_SAMPLE_DATA=false --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For an Android phone connected over USB, preserve the backend's loopback binding:

```powershell
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=USE_SAMPLE_DATA=false --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The iOS simulator can use `http://127.0.0.1:8000` when the backend is on the same Mac.
An actual iPhone needs a reachable local host and platform network permission setup;
its localhost points to the phone. Do not expose the unauthenticated backend publicly.
No API credentials or `.env` files are needed. The API base URL is compile-time
configuration and requires rebuilding after a change.

The service layer sends `POST /analyze` with `multipart/form-data`, binary file part
`image`, and the original filename. The client sets the boundary automatically.
It validates all seven response fields and enum values before rendering. It handles
400/413/415/422/502/503/504 and other HTTP failures, malformed responses, connection
failure and a 660-second end-to-end timeout. Requests are not automatically retried.
Cancel/back closes the pending HTTP client and ignores late results; it does not
guarantee that Ollama immediately stops work already started on the server.

Only the existing contract is used. Safety is never presented as confirmed: even
the contract's `low` safety enum displays an observation-only caution. The exact
server safety note and mission are shown. Context and identification remain labeled
as unverified. Phone-Down asks the user to press the power button; it does not claim
to lock the device, track GPS, enable a sleep mode or perform background activity.

## Checks and builds

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

The Android SDK, an appropriate JDK and accepted Android licenses are needed for
an APK. iOS builds require a Mac with Xcode (`flutter build ios --no-codesign`).
Native camera permissions and actual capture should also be checked on a physical
device; automated tests inject a capture service and do not operate hardware.

Verified on October 8, 2026 with Flutter 3.47.6 and Dart 3.13.5:
`flutter analyze` reported no issues, all 17 tests passed, the Flutter bundle built,
and `flutter build apk --debug --target-platform android-arm64` produced a debug APK.
Tests cover all eight screens, fixture values, capture/preview, cancellation,
permission/API errors, malformed JSON, multipart fields, UTF-8 and large text.
iOS native builds require Mac/Xcode and were not run on this Windows machine.

Optional visual QA screenshots, generated locally and ignored by Git:

```powershell
flutter test test/scout_flow_test.dart --update-goldens --dart-define=CAPTURE_SCREENSHOTS=true
```

## Design and assets

Implemented from the supplied Stitch export `stitch_wildscout_nature_field_companion`:
evergreen/moss tones, pale natural canvas, 24–28px cards, pill buttons, 56px primary
touch targets, and locally bundled Inter and Plus Jakarta Sans fonts. The decorative
fern/forest assets come from the supplied design's image URLs and are bundled for
offline rendering. They are not treated as captured images or identification data.
Font licenses are included next to the fonts. Text stays scrollable and honors the
device text scale. Android lost-image recovery is supported after the OS restarts
the activity while the native picker is open.

The export also contains accounts, GPS, telemetry, cached species counts, percentage
confidence, hardware claims and collection actions. These were omitted to follow
the requested product scope and avoid unsupported claims. No login, database,
cloud inference, location tracking, maps, chat, social UI or gamification is included.

References: [Flutter image picker](https://pub.dev/packages/image_picker),
[Dart HTTP client](https://pub.dev/packages/http). Community design research:
[Building Snap Picker](https://dev.to/coderx06/building-snap-picker-a-beautiful-animated-image-picker-for-flutter-1nf0)
shows the capture/preview flow; its additional social-style picker features were
unnecessary here. The platform-owned picker keeps the dependency set small.
