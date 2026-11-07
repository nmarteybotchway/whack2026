# Developer setup and operations

See [architecture.md](architecture.md) for how the app fits together.

## Toolchain

| Requirement | Source |
| --- | --- |
| Dart SDK `^3.13.7` (use a Flutter stable release that bundles it) | `pubspec.yaml` `environment.sdk` |
| JDK 17 for Android builds | `android/app/build.gradle.kts` (`JavaVersion.VERSION_17`, `JvmTarget.JVM_17`) |
| Android `minSdk` 28 or the Flutter default, whichever is higher | `minSdk = maxOf(flutter.minSdkVersion, 28)` |
| iOS deployment target 15.0 | `ios/Runner.xcodeproj/project.pbxproj` |
| Firebase CLI (to deploy rules and run the emulator) | `firebase.json`, `firebase.assistant-test.json` |
| Python 3 (rules test, `tool/fetch_tesco_stores.py`) | `test/firestore/`, `tool/` |

Then run:

```sh
flutter pub get
```

### Dependencies of note

| Package | Used for |
| --- | --- |
| `firebase_core`, `firebase_auth`, `cloud_firestore` | Anonymous auth and all persistence |
| `camera` | Product scanning (`ScanPage`) and receipt photos (`ReceiptScanPage`) |
| `google_mlkit_text_recognition` | On-device receipt OCR fallback |
| `http`, `crypto` | REST clients (OpenRouter, USDA, FoodBase, Veryfi HMAC signing, Tesco) |
| `speech_to_text`, `flutter_tts` | Assistant voice input/output (`lib/services/`) |
| `rive` | `NutrientGarden` animation (`assets/rive/tree_demo.riv`) |
| `shared_preferences` | Appearance (theme mode + accent) |
| `androidx.health.connect:connect-client:1.1.0` (Gradle) | Health Connect reads in `MainActivity.kt` |

Bundled assets (`pubspec.yaml`): `assets/tesco_stores.json`, `assets/rive/tree_demo.riv`.

## API keys: `lib/secrets.dart`

`lib/secrets.dart` is git-ignored (`/lib/secrets.dart` in `.gitignore`), and
several libraries import it: `openrouter_service.dart`, `nutrition_service.dart`,
`veryfi_service.dart`, `product_identification_service.dart` and
`food_check_demo.dart`. If the file is missing, the app, the tests and the
`tool/` scripts all **fail to compile**. Create it once per checkout:

```sh
cp lib/secrets.example.dart lib/secrets.dart
```

| Constant | Used by | Where to get it | If left empty |
| --- | --- | --- | --- |
| `openRouterApiKey` | `OpenRouterService` (assistant; `tool/fill_food.dart`, `dedupe_food.dart`, `fill_food_images.dart`) | https://openrouter.ai/keys. The default model is the account preset `@preset/glm-flash`, so the key's account needs a preset with that name, or pass `model:` explicitly | Requests fail with `OpenRouterException` (401) |
| `veryfiClientId`, `veryfiUsername`, `veryfiApiKey` | `VeryfiService` (receipt scanning) | https://app.veryfi.com → Settings → API Keys | Receipt scan falls back to on-device ML Kit |
| `foodBaseApiKey` | `ApiProductIdentification` (product scanning) | FoodBase dashboard (`foodbase.dev`) | Scan returns status `unavailable` with "FoodBase API key is not configured." |
| `usdaApiKey` | `NutritionService` (vitamins/minerals) | https://fdc.nal.usda.gov/api-key-signup | USDA rejects the request. Lookups are best-effort, so nutrients are silently missing. `DEMO_KEY` works for testing but is heavily rate-limited |

Never commit `lib/secrets.dart`. The Firebase API keys in
`lib/firebase_options.dart`, `android/app/google-services.json` and
`tool/src/food_store.dart` identify the project and are not secrets.

## Firebase

- Project: `whack-2026-c7898`.
- `lib/firebase_options.dart` (FlutterFire) configures **android, ios, web,
  windows**. **macOS and Linux throw `UnsupportedError`**, so the app cannot
  start on Linux desktop even though a `linux/` folder exists.
- `android/app/google-services.json` is checked in, and the Gradle plugin
  `com.google.gms.google-services` is applied.
- iOS has no `GoogleService-Info.plist`. Firebase is set up from Dart options only.
- `firebase.json` holds the FlutterFire platform mapping and points
  `firestore.rules` at the rules file. There is no `.firebaserc`, so pass
  `--project` explicitly.

Console prerequisites:

1. **Authentication → Sign-in method → Anonymous**: enable it. The app and the
   `tool/` scripts both sign in anonymously.
2. **Firestore**: create the default database.

### Deploying security rules

```sh
firebase login
firebase deploy --only firestore:rules --project whack-2026-c7898
```

Test rule changes against the emulator before deploying (see
[architecture.md → Rules test](architecture.md#rules-test)):

```sh
firebase emulators:exec --only firestore --project demo-assistant \
  --config firebase.assistant-test.json 'python3 test/firestore/assistant_rules_test.py'
```

## Platforms

| Platform | Status |
| --- | --- |
| Android | Primary target. Camera, ML Kit, voice and Health Connect all work here |
| iOS | Builds (Firebase options, camera/microphone/speech usage strings in `ios/Runner/Info.plist`). No HealthKit, so health tracking shows "Health Connect tracking is available on Android." |
| Web / Windows | Firebase configured. `ScanPage.isSupported` and `ReceiptScanPage` limit the camera to Android/iOS, and Health Connect is Android-only |
| Linux / macOS | Not runnable: `DefaultFirebaseOptions.currentPlatform` throws |

### Android permissions (`android/app/src/main/AndroidManifest.xml`)

- `INTERNET`, `RECORD_AUDIO`
- `android.permission.health.READ_BLOOD_PRESSURE`, `READ_HEART_RATE`,
  `READ_STEPS`, `READ_SLEEP`, `READ_WEIGHT`
- `CAMERA` is added by the camera plugin's manifest merge (`camera_android_camerax`)
- Package-visibility `<queries>` for Health Connect
  (`com.google.android.apps.healthdata`), TTS and speech recognition services
- `HealthPrivacyActivity` handles `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`
  and the `VIEW_PERMISSION_USAGE` alias that Health Connect requires.

## Running on an Android device

Enable USB debugging on the phone, then:

```sh
flutter devices                    # find the device id
flutter run -d <device-id>         # debug build with hot reload
```

Release build and install. The release build type is signed with the
**debug** keystore (`signingConfig = signingConfigs.getByName("debug")`), so it
is fine for demos but not for Play upload:

```sh
flutter build apk --release
flutter install -d <device-id>     # installs build/app/outputs/flutter-apk/app-release.apk
```

Health Connect features need a phone with Health Connect available. On older
Android versions that means installing or updating the Health Connect app.
See [health-data.md](health-data.md).

## Tests and analysis

```sh
flutter analyze
flutter test                       # all Dart tests under test/
flutter test test/health_data/     # one area
```

- Lints: `package:flutter_lints/flutter.yaml`. `analysis_options.yaml` excludes
  `build/`, `android/`, `ios/`, `windows/`, `linux/` and `web/`.
- Live OpenRouter tests are skipped by default. To opt in:
  `flutter test --dart-define=OPENROUTER_LIVE_TEST=true --plain-name live`
  (add `--dart-define=OPENROUTER_LIVE_IMAGE=/path/to/photo.jpg` for the image test).
- The Firestore rules test is Python and runs under the emulator (see above).

## `tool/` scripts

Plain Dart or Python scripts, run from the repo root. The Dart scripts talk to
Firestore over REST (`tool/src/food_store.dart`), signed in anonymously. They
need Anonymous auth enabled, the rules deployed and, where they call
OpenRouter, `lib/secrets.dart`.

| Script | Purpose |
| --- | --- |
| `dart run tool/fill_food_db.dart food.txt [--dry-run] [--full]` | Full food pipeline: `fill_food` → `dedupe_food` → `fill_food_images` → `generate_food` |
| `tool/fill_food.dart`, `tool/dedupe_food.dart`, `tool/fill_food_images.dart`, `tool/generate_food.dart` | Individual pipeline steps (`generate_food` rewrites `lib/food/known_foods.g.dart`) |
| `dart run tool/inspect_food_images.dart [limit]` | Read-only peek at `food_images` (limit 1–10) |
| `dart run tool/tesco_food_dump.dart "CV4 7AL" [out.json] [--details] [--large]` | Dump the Tesco food range near a location |
| `python3 tool/fetch_tesco_stores.py [out.json]` | Refresh `assets/tesco_stores.json` |

Details are in [food-data.md](food-data.md).

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Compile error `Target of URI doesn't exist: '../secrets.dart'` | `lib/secrets.dart` not created |
| App stuck on a spinner at launch | Anonymous sign-in disabled in Firebase Auth, or no network |
| `UnsupportedError: DefaultFirebaseOptions have not been configured for linux` | Running on Linux/macOS desktop; use Android/iOS (or web/Windows) |
| `permission-denied` from Firestore | Rules not deployed, or the write includes a field the rules do not allow (see [architecture.md → Known inconsistencies](architecture.md#known-inconsistencies-code-vs-rules)) |
| Nutrient tracker / garden empty after receipts | USDA lookups failing (empty `usdaApiKey`, or `DEMO_KEY` rate limit). Failures are skipped silently. Results are cached in `nutritionCache`, so later scans of the same food cost nothing |
| Receipt items look like raw OCR lines | Veryfi failed (keys, credits, network) and the ML Kit fallback parsed the text |
| Scan sheet says FoodBase key not configured | `foodBaseApiKey` empty |
| Assistant replies with 401 / errors | `openRouterApiKey` missing, or the `@preset/glm-flash` preset does not exist on that OpenRouter account |
| "Install or update Health Connect on this phone" | Health Connect SDK status is `updateRequired` |
| Health data card shows "Could not collect health data" | Health Connect read permission not granted for every type (see [health-data.md](health-data.md#known-gaps)) |
| `flutter test` cannot bind a socket in a sandbox | Some sandboxes deny localhost sockets; run outside the sandbox |
