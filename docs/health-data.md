# Health data

`lib/health_data/` handles three separate kinds of health data:

| Feature | Data | Source | Stored at |
| --- | --- | --- | --- |
| **Height, weight & BMI** | `heightCm`, `weightKg`, `bmi`, preferred units | Typed in by the user | `users/{uid}/healthProfile/measurements` |
| **Blood-pressure tracking** | Each systolic/diastolic reading with source metadata | Android Health Connect, synced repeatedly | `users/{uid}/bloodPressure/{healthConnectRecordId}` |
| **Health data snapshot** | Latest heart rate, today's steps, last sleep, latest weight, latest blood pressure | Android Health Connect, read once when you opt in | `users/{uid}/healthData/latest` |

All three are owner-only in `firestore.rules`. The assistant can read them
through `get_user_records` with the sources `measurements`, `healthData` and
`bloodPressure` (see [assistant.md](assistant.md)).

Internals: sync behaviour, limits, and the device verification checklist are
in [`lib/health_data/README.md`](../lib/health_data/README.md).

## Where it appears in the UI

| Entry point | Widget | Opens |
| --- | --- | --- |
| Settings → "Height, weight & BMI" | `BodyMeasurementsCard` | `BodyMeasurementsPage` in a bottom sheet (`closeOnSave: true`) |
| Settings → "Health data" switch | `HealthDataCard` | Inline. Switching on calls `HealthDataStore.collectAndStore`; "Delete stored data" removes `healthData/latest` |
| First launch on Android (after sign-in) | `showHealthTrackingIntro` dialog, from `HomePage` | "Connect and upload" → `HealthTrackingController.connect()`; "Not now" just marks the intro as seen |
| *(not placed anywhere at the moment)* | `HealthTrackingCard` | `BloodPressurePage` (connect / refresh / stop / delete, latest 20 readings) → `HeartRatePage` (7-day heart rate read live from Health Connect, not stored) |

## Code map

| File | Role |
| --- | --- |
| `models/body_measurements.dart` | `BodyMeasurements`: imperial↔metric conversion, `bmi`, `isValid` (0 < height ≤ 300 cm, 0 < weight ≤ 1000 kg) |
| `body_measurements_page.dart`, `body_measurements_card.dart` | Form and summary for manual measurements |
| `sources/blood_pressure_source.dart` | `BloodPressureSource`: Dart side of the `sentinel/health_connect` method channel (`availability`, `hasPermission`, `requestPermission`, `trackingSettings`, `saveTrackingSettings`, `read` (blood pressure), `readHeartRate`, `readSteps`, `readSleep`, `readWeight`) |
| `sync/blood_pressure_sync.dart` | `BloodPressureSync`: reconciles a rolling 29-day window into Firestore; `deleteUploaded()` |
| `health_tracking_controller.dart` | `HealthTrackingController`: per-session opt-in state, 60 s foreground timer, lifecycle observer |
| `health_tracking_card.dart` | `showHealthTrackingIntro` and `HealthTrackingCard` |
| `blood_pressure_page.dart`, `heart_rate_page.dart` | Tracking controls/readings; heart-rate viewer |
| `health_data_store.dart` | `HealthDataStore`: builds the `healthData/latest` snapshot |
| `health_data_card.dart` | `HealthDataCard`: opt-in switch for the snapshot |
| `repositories/` | Placeholder (README only) |
| Native: `android/app/src/main/kotlin/com/example/hackathon/MainActivity.kt` | Health Connect client, permission launcher, paginated `readRecords`, and the `sentinel_health` SharedPreferences used for tracking settings |
| Native: `HealthPrivacyActivity.kt` | Permission-rationale / permission-usage screen required by Health Connect |

## Data sources

Only **Android Health Connect** is supported. Nothing for iOS HealthKit is
implemented. On any platform other than Android,
`HealthTrackingController.initialize()` sets the status to "Health Connect
tracking is available on Android." Readings from Samsung Health or a watch
show up only if that app writes them to Health Connect.

The native side asks for read access to five record types in one request:
`BloodPressureRecord`, `HeartRateRecord`, `StepsRecord`, `SleepSessionRecord`
and `WeightRecord`, matching the `android.permission.health.READ_*` entries in
`AndroidManifest.xml`. No write permission is requested.

- `requestPermission` returns true when **any** permission is granted.
- `hasPermission` is true when at least one of the five is granted.
- Each `read*` call checks its own record type and throws
  `SecurityException` (surfaced as `read_failed`) if that type is not allowed.

## Blood-pressure sync

```text
Health Connect BloodPressureRecord
  -> MainActivity (readBloodPressure, paginated)
  -> BloodPressureSource.read
  -> BloodPressureSync.refresh (29-day window, diff, batched ≤400 ops)
  -> users/{uid}/bloodPressure/{recordId}
  -> BloodPressurePage snapshot stream
```

- When it runs: on `connect()`, on app resume, and every 60 s while the
  user is opted in and the app is in the foreground. `HomePage` owns the
  controller, so it keeps running whichever tab is open. It is not a
  background service.
- Opt-in persistence: `introSeen` is per install and `enabled:{uid}` is
  per account, both kept in native SharedPreferences `sentinel_health`.
  Tracking resumes on restart only if Health Connect is available and read
  permission is still granted.
- If permission is revoked, the next refresh disables tracking.
  `deleteUploaded()` stops tracking and deletes every document in
  `bloodPressure`. It does not touch Health Connect.
- Each document holds `id`, `systolic`, `diastolic` (mmHg), `measuredAt`,
  `sourceModifiedAt`, `sourceApp`, `unit: 'mmHg'`,
  `provider: 'health_connect'`, and `deviceManufacturer`/`deviceModel` when
  present.

## Health data snapshot

`HealthDataStore.collectAndStore(uid)` reads the last 30 days of each record
type and merges the results into `users/{uid}/healthData/latest`:

| Field | Derived as |
| --- | --- |
| `heartRateBpm` | Mean of the `bpmSamples` in the most recent heart-rate record |
| `steps` | Sum of step records starting since local midnight today |
| `sleepMinutes` | Duration of the most recent sleep session |
| `weightKg` | Most recent weight record |
| `systolicMmHg`, `diastolicMmHg` | Most recent blood-pressure record |
| `updatedAt` | Server timestamp |
| `optedIn` | Written separately by `HealthDataCard` (`true`/`false`) |

Metrics with no data are left out. If nothing at all was found, nothing is
written. This is a **one-off snapshot taken when the switch is turned on**.
Nothing refreshes it afterwards.

## Height, weight & BMI

The form accepts centimetres or feet + inches (whole feet, 0 ≤ inches < 12)
and kilograms or pounds. Values are stored in cm/kg without rounding,
together with the units you chose. `bmi = weightKg / (heightCm/100)²`, and the
rules require the stored `bmi` to match that formula to within 1e-6. Each save
replaces the document; no history is kept. This is independent of Health
Connect.

## Setup

1. Complete [setup.md](setup.md), including enabling Anonymous auth and
   deploying `firestore.rules`.
2. Use an Android phone (API 28 or later) with Health Connect. Give your
   source app (for example Samsung Health) Health Connect write access.
3. Accept the intro dialog, or turn on Settings → Health data.

## Tests

`test/health_data/`:

- `body_measurements_test.dart`: BMI and unit conversion.
- `blood_pressure_source_test.dart`: channel arguments and error propagation.
- `health_tracking_controller_test.dart`: intro, permission denial and resume
  behaviour, using a mocked `sentinel/health_connect` channel.

## Known gaps

- `HealthTrackingCard` is defined but not placed on any page. After the intro
  dialog, the only way to reach `BloodPressurePage`/`HeartRatePage`
  (refresh, stop, delete uploaded readings, heart-rate view) is to add the
  card back. `SettingsPage` already receives the `tracking` controller.
- `HealthDataCard` calls `collectAndStore` without checking availability or
  calling `requestPermission`. It only works after permission has been
  granted elsewhere (the intro dialog or `HeartRatePage`). Because each
  native `read*` throws when its own type is not granted, a single missing
  type (for example sleep) fails the whole snapshot.
- `HealthDataCard._load` uses `doc.get('optedIn')`, which throws a
  `StateError` (not a `FirebaseException`, so it is not caught) when
  `healthData/latest` or its `optedIn` field does not exist. The switch then
  stays off, but the error goes unhandled.
- The "Health data" card text says it is "Collecting your readings", but the
  snapshot is taken only once (see above).
