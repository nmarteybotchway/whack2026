# Shopping assistant

The bottom bar has an Assistant destination immediately left of Settings. The
session is shared with the camera's “Ask about this product” chat entry. It uses
OpenRouter's `@preset/glm-flash` preset; a live capability check during development
resolved it to `z-ai/glm-5.3-flash` and returned a valid function call.

## Using it

- Type a request or tap the microphone, review the transcript and press Send.
- Replies can be spoken, stopped or replayed. Leaving the assistant or
  backgrounding the app stops microphone capture and playback.
- Ask about your profile, health readings, food history, stored food guidance
  and personalized alternatives. Ask to see food images to display image cards.
- Preference changes and manual food logs appear as proposals. Confirm or cancel
  before saving. A failed save can be retried with the same action ID.
- Manual logs appear separately in History as eaten or purchased; they do not
  modify receipt nutrient totals.
- Open Settings → Assistant, or use the chat's settings button, to customize
  name, tone, response length, encouragement, humor, instructions and voice.
  Preview produces a sample without executing tools or changing conversation
  history. Preferences are stored per signed-in user.
- Scan a product and open the camera's chat button to discuss it using the same
  conversation. This version uses deliberate voice turns; it does not continuously
  listen while walking or operate in the background.

## Data and execution

`AssistantController` owns the session, bounded tool loop, pending confirmation
and audio lifecycle. `FirestoreAssistantRepository` implements the data/tool
contract. Personal tools are bound to the constructor's authenticated UID; the
model cannot select arbitrary user IDs or Firestore paths.

Personal sources include the root profile, body measurements, latest health
summary, blood-pressure records, diet/receipt history, manual food entries and
assistant settings. History tools return bounded pages with continuation cursors.
Shared tools read the food catalog, alternatives, stored food news, cached
nutrition and `food_images`. Missing sources and unknown constraints remain
explicit in tool results.

`food_images/{Food.idFor(name)}` contains `name`, `url`, `page` and optional
`updatedAt`. The app resolves the stored URL and renders it with the matching
food name and source page. A broken/missing image does not prevent a text reply.

Writes use validated proposals and transactions that save the mutation together
with an immutable `users/{uid}/assistantActions/{id}` result marker. Profile
proposals check the original target-field values before committing. Manual
entries use `users/{uid}/foodEntries/{entryId}`. Conversation history is held in
memory and cleared when the signed-in session ends.

## Setup and verification

Use the existing git-ignored `lib/secrets.dart` setup from
`lib/secrets.example.dart`. The local prototype uses the existing direct
OpenRouter transport. A distributed application using a shared OpenRouter key
still needs an authenticated backend that keeps that key server-side.

The checked-in Firestore rules include the new profile, health-summary,
assistant-settings, manual-entry and action-marker paths. They must be deployed
to the intended Firebase project for those operations to work under these rules;
implementation and local tests do not deploy them.

Android microphone permission and iOS microphone/speech-recognition purpose
strings are included. Voice requires a supported device recognizer/TTS engine
and permission; typed chat remains available if voice fails.

From the repository root:

```sh
flutter analyze
flutter test
flutter build apk --debug
firebase emulators:exec --only firestore --project demo-assistant \
  --config firebase.assistant-test.json 'python3 test/firestore/assistant_rules_test.py'
```

The emulator needs a recent Java runtime. `test/firestore/assistant_rules_test.py`
refuses to run against a non-local Firestore host and tests only the demo
project. Production user records are not used by these tests.

Real-device validation is still required for permission denial, silence/noisy
stores, selected voice availability, interruptions, and camera/microphone
coexistence. The iOS build must be checked on macOS.
