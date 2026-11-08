# Shopping assistant

The bottom bar has an Assistant destination immediately left of Settings. The
session is shared with the camera's Shopping companion panel and full-chat entry. It uses
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
- In Scan, tap **Start** on Shopping companion to keep the camera visible while
  hearing summaries, asking questions and seeing alternative image cards. The
  camera stays on the live preview until you press the shutter or the assistant
  requests a fresh photo to identify a product.
  Start speaks a greeting and listens for questions automatically, returning
  to listening after replies. This is turn-based: the microphone is stopped
  before the assistant speaks and remains closed while it prepares or answers.
  Tap the mic's **Interrupt and talk** action to cancel a reply and listen again;
  speaking over playback does not trigger interruption. A two-second pause
  submits recognized speech automatically. Typed questions still work.
  General questions work before the first scan.
  Say “show me more” or use **Details** for the original scan sheet or
  the app-bar chat button to open the full shared conversation.
- Backgrounding or an interruption pauses camera companion audio and microphone
  activity without ending the session, clearing its draft, or cancelling its
  pending answer. Returning resumes an already-active companion without another
  greeting. Stop session still ends it explicitly. Automatic listening runs only
  during the foreground shopping session.
- Visited tabs retain their page state when switching tabs. Conversation messages,
  typed and shopping drafts, current product context, and the last identified scan
  are saved locally per user. After an app restart, reopen the scanner to access
  the last product and explicitly start a new voice session.

The native duplex implementation is retained for future experiments but is not
used by the current shopping flow. Turn-based mode uses the ordinary device
recognizer and does not require Android 13 external audio injection or hardware
echo cancellation. Recognition availability, permission, language and network
requirements still depend on the installed recognizer. Test on the target phone.

## Camera shopping companion

`ShoppingCompanionController` coordinates the existing `AssistantController`
without creating a second chat session. The default voice is Kokoro, with the
device TTS engine used if owned Kokoro playback fails. Speaking claims the audio
turn before stopping recognition, and foreground listening resumes after replies.
The panel shows preparing/speaking status, an interrupt button, and Retry speech
on failure. A paused microphone stays paused until explicitly resumed.

Kokoro synthesis/playback failures reject the awaiting utterance and invalidate
queued audio, allowing fallback instead of leaving the controller stuck speaking.
Completion is bounded by a reply-length-based watchdog. Model request cancellation
and late recognition results are guarded by session/operation epochs.

New scans update the
selected product, invalidate unfinished product-specific model turns, and stop
old speech. Prior conversation stays available. Product identity uses a GTIN,
catalog ID, or normalized name/brand/variant/size. Repeat announcements are
suppressed during a short cooldown; late responses cannot describe the next
product as if they belonged to it.

`ProductBriefingService` formats a short, deterministic summary from the same
food recommender used by the result sheet. It includes stored alerts,
preference/condition conflicts and nutrient information, respects declined
swaps, and checks candidate alternatives before showing up to three cards.
Missing catalog/profile evidence is stated explicitly. Images come from
Firestore metadata and may fail independently of the text summary.

Automatic summaries do not call model tools or save data. Follow-up questions
use OpenRouter with the user's saved personality and shorter camera replies.
Proposed writes still require the visible Confirm/Cancel controls. Capture and
announcements yield while the user listens, types, thinks or confirms an action.

## Data and execution

`AssistantController` owns the session, bounded tool loop, pending confirmation
and audio lifecycle. `FirestoreAssistantRepository` implements the data/tool
contract. Personal tools are bound to the constructor's authenticated UID; the
model cannot select arbitrary user IDs or Firestore paths.

Personal sources include the root profile, body measurements, latest health
summary, blood-pressure records, diet/receipt history, manual food entries and
assistant settings. History tools return bounded pages with continuation cursors.
Shared tools read the food catalog, stored food news, cached nutrition and
`food_images`; buy/avoid decisions and alternatives come from the same
recommendation engine as the scan result sheet, so the two always agree
(see [recommendations.md](recommendations.md) and
[food-data.md](food-data.md)). Missing sources and unknown constraints remain
explicit in tool results.

### Tools

Defined in `FirestoreAssistantRepository._toolDefinitions`
(`lib/assistant/assistant_repository.dart`), plus `get_current_product`, which
`AssistantController` adds itself. Each repository call times out after 15
seconds and errors come back as `{"error": <code>, "available": false}`. A
turn runs at most 6 tool calls (`_maxToolCalls`).

| Tool | Arguments | Returns |
| --- | --- | --- |
| `get_user_summary` | – | `profile` (`users/{uid}`), `measurements` (`healthProfile/measurements`), `healthData` (`healthData/latest`), `authProfile`; unavailable sources are marked per key. |
| `get_preferences` | – | `religion`, `dietary`, `health_conditions` from `users/{uid}`. |
| `get_user_records` | `source` (`profile`, `measurements`, `healthData`, `assistantSettings`, `bloodPressure`, `diet`, `receipts`, `foodEntries`), `limit` 1–50 (default 20), `cursor`, `startDate`, `endDate` | `{source, records, nextCursor, hasMore}`, newest first. `diet` reads the 14-day `DietWindowService` window; single-document sources reject date filters. |
| `lookup_food` | `name` | `{found, food: {id, ...food/{id} fields}}`. |
| `search_foods` | `query` (ID prefix after `Food.idFor`), `limit` 1–30 (default 10), `cursor` | `{foods, hasMore, nextCursor}`. |
| `get_alternatives` | `name` | Delegates to `FoodRecommendationService.recommendFor`, the same engine as the scan sheet: `{found, food, shouldAvoid, canBuy, reasons, excessNutrients, boostsNutrients, swapDeclined, source, updatedAt, alternatives}`, where each of up to 12 ranked alternatives has `name`, `knownConflicts`, `food`, `source`, `updatedAt`. Unknown foods give `{found: false, alternatives: []}`. See [recommendations.md](recommendations.md). |
| `get_food_news` | `name` | `{localNews, generalInfo, hasAlerts, source, updatedAt}`; empty fields read "No negative news discovered". |
| `get_nutrition` | `name` | `{found, record, source}` from `nutritionCache/{trimmed lower-case name}`. |
| `show_food_images` | `names` (1–8) | Image cards from `food_images` (see below). |
| `propose_preference_change` | `field` (`religion`, `dietary`, `health_conditions`), `value`, `operation` (`add`, `remove`) | A pending action; nothing is saved until confirmed. |
| `propose_food_log` | `name`, `localDate`, `kind` (`eaten`, `purchased`), optional `amount` | A pending action for `users/{uid}/foodEntries`. |
| `get_current_product` | – | The last scanned product (set by `ScanPage` via `setCurrentProduct`), or `{available: false}`. |

`food_images/{Food.idFor(name)}` contains `name`, `url`, `page` and optional
`updatedAt`. The app resolves the stored URL and renders it with the matching
food name and source page. A broken/missing image does not prevent a text reply.

Writes use validated proposals and transactions that save the mutation together
with an immutable `users/{uid}/assistantActions/{id}` result marker. Profile
proposals check the original target-field values before committing. Manual
entries use `users/{uid}/foodEntries/{entryId}`. Conversation display messages and
unsent drafts are cached in local preferences under the signed-in user's ID.
Restoration rebuilds plain conversation context; pending tool calls and unconfirmed
actions are not replayed after a process restart. Clear conversation also clears
the saved conversation and drafts. Cached sessions are local to this installation.

## Setup and verification

Use the existing git-ignored `lib/secrets.dart` setup from
`lib/secrets.example.dart`. The local prototype uses the existing direct
OpenRouter transport. A distributed application using a shared OpenRouter key
still needs an authenticated backend that keeps that key server-side.

The checked-in Firestore rules include the new profile, health-summary,
assistant-settings, manual-entry and action-marker paths. They must be deployed
to the intended Firebase project for those operations to work under these rules;
local tests do not deploy them. The reviewed rules were deployed to
`whack-2026-c7898` during the Shopping companion rollout, including the newer
remembered-swap and nutrient-garden fields.

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
