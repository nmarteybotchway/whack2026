# gemini_wrapper

A Flutter/Dart-native wrapper service for Google Gemini, for use by the other
services in this repository (`todo_app`, `budget_tracker`, …).

Simplified I/O contract:

- **In**: a text prompt, a mandatory `Schema` describing the output shape, and
  an optional JPEG image.
- **Out**: the model's text response, always constrained to the schema
  (`responseMimeType: application/json`), so output is deterministic per the
  caller's declared shape.

## Data contract

| Item | Value |
|---|---|
| Image format | **JPEG only** (`image/jpeg`) — fixed |
| Image color | Any standard sRGB JPEG; no preprocessing needed |
| Image size | ≤ 19 MB of raw bytes (Gemini caps inline requests at 20 MB total) |
| Image bytes | Raw `Uint8List` (e.g. `XFile.readAsBytes()` from `ImagePicker`) |
| Response schema | **Mandatory** on every call |
| Output | Text constrained to the schema (structured JSON; natural language via descriptive schema fields) |

## Usage

Add as a path dependency in the consuming app's `pubspec.yaml`:

```yaml
dependencies:
  gemini_wrapper:
    path: ../src/gemini_wrapper
```

Then:

```dart
import 'package:gemini_wrapper/gemini_wrapper.dart';

final service = GeminiService(); // key from lib/secrets.dart

// Prompt-only (structured JSON out).
final parsed = await service.generate(
  prompt: 'Extract the action items from this note.',
  responseSchema: Schema.object(properties: {
    'items': Schema.array(
      items: Schema.string(),
      description: 'Action items, in order.',
    ),
  }),
);

// Prompt + optional JPEG image.
final receipt = await service.generate(
  prompt: 'Read this receipt and return the total.',
  responseSchema: Schema.object(properties: {
    'merchant': Schema.string(description: 'Merchant name as printed.'),
    'total': Schema.number(description: 'Total amount as a number.'),
  }),
  image: GeminiImage(await pickedFile.readAsBytes()),
);
```

### API key handling

The key lives in `lib/secrets.dart`, which is git-ignored. Create it once per
checkout (including each worktree) from the committed template:

```bash
cp lib/secrets.example.dart lib/secrets.dart
```

then set `geminiApiKey` in it. `GeminiService()` uses that key by default;
pass `apiKey:` to override it. Never commit `lib/secrets.dart`.

## Structure

```
lib/
  gemini_wrapper.dart      # single import surface; exports the API below
  src/
    gemini_service.dart    # GeminiService + GeminiImage implementation
test/
  gemini_service_test.dart # unit tests + optional live smoke test
```

## Commands

```bash
flutter pub get
flutter analyze
flutter test
```

Optional live smoke test (requires `geminiApiKey` set in `lib/secrets.dart`):

```bash
flutter test --dart-define=GEMINI_LIVE_TEST=true --plain-name "live"
```
