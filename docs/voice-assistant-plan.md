# Voice assistant implementation plan

Status: initial implementation added 7 November 2026. See
[Shopping assistant](assistant.md) for current behavior and setup. The original
design and repository findings below describe the planning baseline; continuous
hands-free shopping remains a later stage.

## Agreed scope

- Use OpenRouter with `model: '@preset/glm-flash'`.
- Add an **Assistant** destination immediately left of Settings:
  `Home | History | Scan | Assistant | Settings`.
- Support typed messages and speech-to-text input; show replies and speak them
  through text-to-speech.
- Include app actions in the first version, specifically preference changes and
  food logging, alongside product and dietary questions.
- Give the agent read access to all of the signed-in user's information and
  the shared Firestore food data, including alternatives and image references.
  It must be able to show stored food images in its replies.
- Let each user customize the assistant's personality in Settings and from a
  shortcut in Assistant; apply the same preferences in the later camera mode.
- Design one shared assistant session so a later camera overlay can use the
  conversation, voice controls, context and actions without rebuilding them.

## What already exists

| Area | Repository evidence | Work needed |
| --- | --- | --- |
| Navigation | `lib/pages/home_page.dart` has Home, History, central Scan and Settings | Insert Assistant in the right-hand tab group and update Settings' index |
| Model access | `lib/openrouter/openrouter_service.dart` already defaults to the requested preset | Add multi-message and tool-call support; retain `generate()` for existing callers |
| Speech output | `lib/services/text_to_speech_service.dart` wraps `flutter_tts` | Share the service and coordinate stop/completion/error events |
| Speech input | `speech_to_text` is in `pubspec.yaml` | Add a wrapper and permission handling |
| Preferences | Settings reads/writes `religion`, `dietary`, `health_conditions` on `users/{uid}` | Extract a repository shared by Settings and assistant tools |
| Camera | `ScanPage` produces `AnalysisResult` containing `ProductIdentification` | Later publish selected results into assistant context |
| Food history | `ReceiptStore` stores purchased food names and daily nutrient aggregates | Add explicit manual food entries without pretending they are receipts |
| Shared food data | `FoodRepository` and `Food.alternativesFor()` read food documents and rank alternatives | Expose catalog lookup, search and personalized alternative tools |
| Latest main | `origin/main` at `0dfed28` adds `HealthDataStore` and `FoodNewsService` | Integrate these when implementing; latest main was fetched and inspected without merging app changes |
| Food images | Four live `food_images` documents inspected with `tool/inspect_food_images.dart`: `name`, `url`, `page`, `updatedAt` | Add an image-reference repository using the observed schema |

The checked-in Firestore rules have no match granting access to the root
`users/{uid}` document used by Settings. Add and test an owner-only rule for
the profile fields as part of preference actions; otherwise those operations
can fail under these rules. The latest checked-in rules also omit
`users/{uid}/healthData/latest` and `food_images/{food}`. Cover these reads and
new manual-entry/action records with appropriate rules during implementation.

## First-version experience

1. Open Assistant to see the conversation, a text field, Send, microphone,
   voice-output toggle and New conversation.
2. Tap the microphone to start one voice turn. Show partial transcription;
   stop on tap or recognition completion. Keep the transcript editable and
   use Send to submit in the first version.
3. Show a thinking indicator, display the final reply and speak it when voice
   output is enabled. Provide Stop and Replay controls.
4. For a write, show the exact proposed change in an action card, with Confirm
   and Cancel. For example, “Add Vegan to dietary preferences” or
   “Log porridge as eaten today”. Confirmation is enforced by app code.
5. Report success only after the repository confirms the write. A failed write
   remains visible with a retry control; retry must not duplicate it.
6. For “show me alternatives”, display food cards with names, explanations and
   images resolved from Firestore. Read the explanation aloud, keeping image
   metadata and URLs out of speech.

Example: “Make my diet vegan” produces an add-Vegan proposal, preserving other
preferences. “I had porridge for breakfast” proposes an eaten-food entry for
today. If food or date is unclear, ask a follow-up before proposing the write.

Start with Android and iOS, matching camera support. Voice failures leave typed
chat available. Switching tabs retains the transcript but stops listening and
playback; backgrounding does the same. Returning never starts the mic silently.

## Shared design

`AssistantPage / future camera overlay → AssistantController → agent service → OpenRouter`

The controller also coordinates speech input/output, context and a tool executor.

- **AssistantController:** a `ChangeNotifier` owned by the signed-in HomePage
  shell and passed to both entry points. It owns the conversation, current turn,
  pending action, cancellation and voice state; widgets only render and forward
  user events. Dispose and clear it when the signed-in user changes.
- **AssistantAgentService:** builds the system instructions and bounded message
  history, supplies tool schemas, and runs a bounded tool loop. Start with full
  replies; add streaming after the basic turn and action flow is reliable.
- **OpenRouter service:** add typed system/user/assistant/tool messages and a
  chat response that can contain text, tool calls, or both. Tool-only responses
  may have null text; the current text-only parser cannot handle them. Preserve
  call IDs and send tool results using the corresponding IDs.
- **SpeechToTextService:** owns one recognizer instance and exposes availability,
  partial/final text, start, stop, cancellation and failures.
- **TextToSpeechService:** reuse the existing wrapper, with completion/error
  reporting adequate for the controller. One playback owner prevents overlapping
  speech from chat and camera.
- **AssistantContextRepository:** exposes the full user-data access surface
  described below and recent scan context. Include a compact current-user summary
  per turn; retrieve detailed records through tools. Fetch fresh profile data
  before actions and invalidate it after writes. Add timestamps and source
  information to scan context.
- **FoodImageRepository:** resolves catalog food IDs/names into stored image
  references, caches metadata, and supplies typed attachments to the UI. The
  model selects records; the repository resolves their actual locations.
- **AssistantToolExecutor:** validates tool arguments, scopes operations to the
  authenticated user, and calls repositories. The model cannot choose a UID,
  Firestore path or arbitrary function.

Voice states: idle → listening → transcribing → thinking → speaking → idle,
with awaiting-confirmation and recoverable-error states. Stop speech before
opening the mic and stop recognition before playback. Serialize turns, use turn
IDs to ignore late callbacks, and invalidate pending proposals on cancel, new
conversation or user change.

Keep conversation history in memory initially, bounded by a configurable turn
and input-size limit. Preserve complete tool-call/result pairs when trimming.
Do not persist raw audio or full transcripts in this first scope.

## Full user information and shared Firestore data

Access covers every available user-data category, with detailed records fetched
on demand so large histories do not have to fit inside every model request.
This is part of the first version, not postponed to camera integration.

| Source | Information exposed to the agent |
| --- | --- |
| Firebase Auth user | Available profile information such as name and email; credentials/tokens are transport internals |
| `users/{uid}` | Dietary/religious preferences, health conditions and other stored profile fields |
| `users/{uid}/healthProfile/measurements` | Height, weight, BMI, units and update time |
| `users/{uid}/healthData/latest` on main | Stored heart rate, steps, sleep, weight, blood pressure and collection opt-in state |
| `users/{uid}/bloodPressure/{recordId}` | Historical readings and their measurement/source metadata |
| `users/{uid}/diet/{dayId}` | Purchased food history and stored daily nutrition aggregates |
| `users/{uid}/receipts/{receiptId}` | Receipt records when present; an allowed rules path does not guarantee records exist |
| `users/{uid}/foodEntries/{entryId}` (planned) | Manual food logs, including whether eaten or purchased |
| Current assistant session and latest scan | Conversation references, selected product, evidence and uncertainty |
| Shared `food/{foodId}` | All food fields, alternatives matrix, condition/preference tags, local news and general information |
| Shared `nutritionCache/{foodName}` | Available nutrient information with its provenance and update time |
| Shared `food_images/{food}` | Metadata locating images of foods and alternatives |

Create a source registry so each new user collection gets a retrieval adapter
and test. Firestore client access does not recursively discover arbitrary
subcollections: the agent's complete access surface must follow the app's schema
as it evolves. Each adapter accepts bounded pages and date ranges, returns a
continuation cursor, and distinguishes empty, unavailable and permission-denied
results. Histories remain fully traversable across pages, rather than permanently
limited to the latest summary.

Bind personal retrieval to the authenticated UID in app/backend code. Shared
food collections are readable across the catalog; other users' private records
are outside this scope. Broad read access does not introduce arbitrary writes:
the first action set remains preference changes and manual food logging.
Use existing stored health data; preserve the existing opt-in flow for acquiring
additional device readings.

Return units, source paths and available timestamps with retrieved values. On
main, `healthData/latest` merges metrics and supplies one document update time;
that is not evidence that every metric was measured at that time. Prefer record
timestamps when present and label unknown metric freshness explicitly. Preserve
the distinction between manual weight and device weight, purchases and meals.

For alternatives, resolve a product name into a canonical catalog record and
use its stored alternatives matrix with the user's conditions and preferences.
Reuse `Food.alternativesFor()` for candidate ranking, then evaluate each candidate
against all applicable constraints. Its vote ranking alone does not establish
compatibility with every condition. Return why each candidate was selected,
known conflicts and missing evidence. Stored news comes through `FoodNewsService`
on main; missing stored news does not establish that no current alert exists.

## Images in assistant replies

Use structured conversation parts: text, food cards, image attachments and action
cards. A `show_food_images` tool selects food records, and the repository reads
`food_images/${food}` to resolve each reference. Images appear alongside the
corresponding recommendation and can open in a larger preview. TTS speaks food
names and relevant descriptions, never download URLs.

Luna inspected four live documents on 7 November 2026 using
`dart run tool/inspect_food_images.dart` (default limit 4; maximum 10). The script
only reads Firestore; unless supplied an existing token, authentication creates
an anonymous Firebase Auth account. It strips URL query strings and fragments
from inspection output.

Observed document IDs: `100%_rye_bread`, `almond_milk`, `apple_slices`, `apples`.
All four contain:

| Field | Use |
| --- | --- |
| `name` | Stored food display name |
| `url` | Direct HTTPS image URL; observed URLs are Wikimedia thumbnails |
| `page` | Stored image source-page reference |
| `updatedAt` | Stored metadata freshness value; validate its type when parsing |

For example, `food_images/almond_milk` has `name: 'almond milk'` and
`page: 'https://en.wikipedia.org/wiki/Almond_milk'`, alongside its thumbnail URL.

Start lookups with `Food.idFor(name)` (lowercase with whitespace/slashes replaced
by underscores). The sample is consistent with that convention, including
preserved punctuation such as `%`, but does not prove every document follows it.
Check the stored name and handle unmatched names explicitly. A first-version
image attachment can contain `foodId`, `name`, `url`, `sourcePage` and
`updatedAt`, populated by the repository rather than invented by the model.

Load the stored HTTPS `url`, retain `page` as a source link, and cache thumbnails.
Handle missing documents, malformed fields, broken links and unavailable images
without failing the text reply. Bind each attachment to the tool-selected food
record. Firebase Storage resolution is unnecessary for the observed schema; add
an adapter if stored references change later. Inspecting metadata does not verify
that every remote image URL is still fetchable.

Showing an image to the user does not require model vision. If a later question
requires inspecting the picture itself, first verify that the preset supports
image input and attach the selected image explicitly; do not assume text/tool
support also implies vision support. Reuse the same cards in the camera overlay.

## Personality customization

Add **Settings → Assistant**, also reachable from an Assistant-page settings
button. Start with three presets: Friendly coach, Calm guide and Direct
assistant. Presets populate editable controls rather than selecting different
models. All continue to use `@preset/glm-flash`.

First-version controls:

- Optional assistant display name (default Assistant).
- Tone preset and answer length: short, balanced or detailed.
- Encouragement: minimal or supportive; humor: off or light.
- Optional custom instruction, for example “Be practical, avoid emojis, and
  explain why you suggest a substitute.” Limit this to 1,000 characters.
- Voice output enabled/disabled, device voice/locale and speech speed. Available
  voices depend on the device; keep a fallback if a saved voice is unavailable.

Save a validated configuration at `users/{uid}/assistantSettings/preferences`
with a schema version and server update timestamp. Add owner-only rules and
include this source in the user-data registry. Use defaults when absent, support
Reset to defaults, and retain preferences across app restarts. Device-specific
voice IDs may need local overrides when moving between devices.

Compose each model request from app behavior/tool rules, the current personality
configuration, retrieved user/product context and conversation history. Keep
custom instructions in an explicitly labelled lower-priority preference message;
they cannot grant tools, bypass action confirmation or change authenticated data
scope. The app enforces tool permissions and confirmations independently of
prompts. Apply edits to the next turn without deleting conversation history.

Offer **Preview personality** before saving: generate a short sample response
with the proposed settings and optionally read it aloud. Preview has no write
tools and does not alter the real conversation. In camera mode, use the same
personality with shorter spoken responses appropriate to shopping.

Personality influences phrasing, warmth, humor and detail. Stored user health
facts and evidence for recommendations remain unchanged. A “confident” style
must still express missing information rather than imply unsupported certainty.

The user can later say “Be more concise” through a
`propose_assistant_settings_change` tool, using the existing action preview and
confirmation flow. Initial implementation can ship the Settings controls first.

Acceptance: settings survive restart, remain isolated by UID, affect the next
turn, reset correctly, and fall back when a voice is unavailable. Preview must
not execute app actions; custom instructions cannot bypass confirmed writes.

## Tools and writes

| Tool | Behavior |
| --- | --- |
| `get_user_summary` | Read a compact summary spanning all available user-data categories |
| `get_preferences` | Read the current user's profile/preferences |
| `get_user_records` | Retrieve registered user-data sources with validated date filters, pagination and available provenance |
| `get_current_product` | Return the latest selected scan or explicitly report none |
| `lookup_food` / `search_foods` | Retrieve all stored fields for matching catalog foods; support bounded browsing/search rather than only exact names |
| `get_alternatives` | Rank stored alternatives using the full relevant user context and report constraints/evidence |
| `get_food_news` / `get_nutrition` | Read stored food news and nutrition with provenance |
| `show_food_images` | Resolve stored image references and add food/image cards to the reply |
| `propose_preference_change` | Stage add/remove changes for dietary, religious or health-condition fields |
| `propose_food_log` | Stage a manual food entry with name, local date, eaten/purchased kind, and any user-provided amount |

Writes follow: model proposal → schema and domain validation → user confirmation
→ repository commit → tool result → final assistant reply. A proposal tool can
return pending status; confirmation is a later app event that resumes the agent
with the verified outcome. Spoken “yes” can be added later and must bind to one
active proposal; use buttons first.

Validate preference values using existing enums/options, preserving supported
custom values. Apply preference patches transactionally against fresh data so
unrelated settings survive. If the target fields changed after the proposal,
refresh the preview before saving. Settings must reflect assistant updates.

Manual logs should use `users/{uid}/foodEntries/{entryId}` and record food name,
local day, kind, optional amount, source `assistant`, and server creation time.
Do not require a fictional receipt price. Existing History describes purchases;
extend it to show manual entries with their kind clearly labelled. Keep eaten
entries separate from the current purchased-food nutrient totals, and do not
invent portion nutrition. No legacy receipt migration is required for this scope.

Give each confirmed write a stable action ID and record its result under the
user's subtree. Commit the action marker and mutation atomically so retries and
repeated model calls cannot apply the same action twice. Bound tool execution
to a small configurable number of iterations; reject unknown tools or malformed
arguments. A cancelled/unconfirmed proposal cannot enter the write path.

## Model and platform setup

- Verify that the account's `glm-flash` preset resolves to a model/provider that
  supports tool calling. The slug alone does not establish those capabilities.
  Perform a minimal text and tool-call smoke test during implementation; do not
  silently switch to a different model if the preset needs adjustment.
- Keep replies short and suitable for being spoken. Ask for missing details;
  never claim an action completed without a successful tool result. Treat label
  text and product data as evidence, not instructions. Missing ingredient data
  must remain explicit when explaining dietary/allergen suitability.
- Add Android `RECORD_AUDIO` permission and iOS microphone and speech-recognition
  usage descriptions. Android recognition/TTS service queries already exist.
  Test runtime denial and unavailable recognizers on real devices. Device speech
  recognition can depend on network services; do not promise offline voice.
- Existing OpenRouter calls use a key from `lib/secrets.dart`. The local
  prototype can reuse this transport. Before distributing the app with a shared
  key, route requests through a Firebase-authenticated backend with server-held
  credentials, request limits and the same preset. No backend implementation is
  currently present in this repository.

## Camera integration and walking mode

The camera stage adds a mic/status overlay to `ScanPage`, injected with the same
controller. Feed `AnalysisResult.identification` into context after a successful
scan; do not send every preview frame to the chatbot. The current camera uses
`enableAudio: false`, leaving microphone capture to the voice service.

In an explicitly enabled shopping session, speak a short summary when a new
product is identified. Deduplicate repeated scans, expire stale context, and
attach each response to its product ID so a delayed answer is not presented as
being about the next item. Queue or replace announcements so they never overlap
the user's voice turn or a pending action confirmation. Retain the existing
result sheet until the overlay interaction has been reviewed.

The hands-free stage evaluates reliable conversation while walking. The
current `speech_to_text` package is intended for short phrases, not continuous
or always-on listening. Keep the speech wrapper replaceable so a streaming STT
service can be introduced with voice activity detection, echo handling and
interruption support. Test shop noise, headphones, audio focus and reconnects.
Walking mode is foreground-only initially; background operation is a separate
requirement.

## Implementation order and acceptance

1. **Text agent and actions:** check preset capabilities; extend chat transport;
   incorporate relevant latest-main services; build shared controller and the
   complete user/shared-data retrieval registry; implement food-image resolution
   and rich cards; add Assistant navigation, typed chat, proposal cards,
   preference writes and manual food logging. Add saved personality controls,
   request composition and personality preview. Update rules and History.
   Deliverable: personalized multi-turn chat can explain stored alternatives,
   show their images, retrieve user histories and perform both confirmed actions.
2. **Voice:** wrap recognition, reuse TTS, add permissions and lifecycle controls,
   and connect saved voice/locale/speed preferences.
   Deliverable: speak a request, review/send it, read/hear the reply and stop it.
3. **Camera:** pass the shared controller into ScanPage and publish identified
   products. Deliverable: ask “what about this one?” and receive a reply grounded
   in the current scan without losing the Assistant conversation.
4. **Hands-free shopping:** assess streaming recognition and interruption using
   real store trials. Deliverable: foreground conversation meets measured noise,
   latency and recovery requirements before continuous listening is promised.

Automated checks should cover multi-turn/tool-only responses, malformed tool
arguments, confirmation gating, exactly-once writes, cancellation races, owner
rules, fresh settings after a write, manual logs appearing in History, and tab
placement/session retention, retrieval coverage across all registered sources,
pagination, isolation between users, alternative ranking with multiple constraints,
and image-to-food matching/missing-image fallbacks. Preserve existing OpenRouter
tests. Run analyze and
relevant Flutter tests; use the Firebase emulator for rules and write behavior.

Real-device checks should cover mic denial, recognizer/TTS failure, silence,
network timeout, rapid mic taps, stopping playback, tab changes, backgrounding,
and camera/mic coexistence. Measure recognition completion, model response and
speech-start latency separately. Live API checks are implementation validation,
not something performed by this planning document.

## References

- [OpenRouter presets](https://openrouter.ai/docs/guides/features/presets)
- [OpenRouter tool calling](https://openrouter.ai/docs/guides/features/tool-calling)
- [speech_to_text package and limitations](https://pub.dev/packages/speech_to_text)
- [flutter_tts package](https://pub.dev/packages/flutter_tts)
