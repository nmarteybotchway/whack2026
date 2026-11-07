# Preferences: manual height and weight

The bottom of Settings → Preferences shows a `BodyMeasurementsCard`, matching
the beliefs and dietary cards. It displays the saved height, weight and BMI;
tapping opens `body_measurements_page.dart` in a bottom sheet. Saving closes the
editor and updates the summary through Firestore. Beliefs and dietary edits
save when their Done button is tapped. It loads and saves the
signed-in user's latest `heightCm`, `weightKg`, calculated `bmi`, selected
`heightUnit` (`cm` or `ft_in`), `weightUnit` (`kg` or `lb`), and server `updatedAt` at:

`users/{uid}/healthProfile/measurements`

Height accepts centimetres or feet and inches; weight accepts kilograms or pounds.
Stored measurements are normalised to centimetres and kilograms, with BMI calculated
as weightKg / (heightCm / 100)². BMI is displayed to one decimal place and saved
without display rounding. Saved values and preferred units prefill the form on
return; existing records without unit preferences default to cm/kg.
Both measurements are required;
validation rejects non-finite, non-positive, and out-of-range values. Saving again
replaces the current measurements rather than creating a history.

Deploy `firestore.rules` to enable owner-only access to the new profile document:
`firebase deploy --only firestore:rules --project whack-2026-c7898`.

The standalone Health tab has been removed. The Health Connect implementation
is preserved below for later but is not routed into the current UI.

---

# Blood pressure collection

Implemented flow:

```text
Android Health Connect BloodPressureRecord
  -> native read-only method channel
  -> BloodPressureSource
  -> BloodPressureSync
  -> users/{uid}/bloodPressure/{healthConnectRecordId}
  -> Firestore snapshots -> Health tab
```

Both systolic and diastolic values come from the same source record, in mmHg.
Source IDs, package name, device metadata (when present), measurement time and
source modification time are preserved. No Health Connect write permission is
requested. The Health tab asks explicitly before reading/uploading.

## Setup

Firebase client configuration already exists for `whack-2026-c7898` in
`lib/firebase_options.dart` and `android/app/google-services.json`.
No service-account key or Health Connect API key is required in the app.

1. Install Flutter matching `pubspec.yaml` and run `flutter pub get`.
2. Enable Anonymous sign-in in Firebase Authentication (the existing guest flow).
3. Create the default Cloud Firestore database in the intended region.
4. Sign in to the Firebase CLI with an account allowed to manage that project,
   then deploy the included owner-only rules:
   `firebase deploy --only firestore:rules --project whack-2026-c7898`.
   Review/merge any existing deployed rules first: the local rules currently
   grant access only to this feature's collection.
5. Run on an Android phone (minimum API 28) with Health Connect available; older
   Android versions may require installing/updating the Health Connect app.
6. Sign in, open Health, choose Connect and upload, and grant blood pressure read
   access. Enable your source app's Health Connect write permission separately.

## Behaviour and limits

- Checks a rolling 29-day window on connect, resume, and every 60 seconds while
  the Health tab is open. It stops when the tab is disposed or the app pauses.
- Uses paginated native reads. A failed read never triggers cloud deletions.
- Reconciles corrections and deletions inside that window; older uploaded records
  remain until explicitly deleted. This is a bounded prototype sync, not a full
  historical Changes API integration.
- Skips unchanged records; chunks cloud writes/deletes to at most 400 operations.
- Firestore subscriptions deliver newly uploaded records to authenticated clients.
  Health Connect is not a sensor stream, and Firebase cannot accelerate watch sync.
- Stop sync stops future refreshes; an upload already submitted may finish. Delete
  uploaded readings removes cloud records and stops refreshes. Reconnecting
  imports available source records again. Firestore SDK caches may retain local
  copies; cloud deletion is not a device-cache erasure mechanism.
- No background worker, carer access, or iOS HealthKit integration is included.
- Samsung Health's blood pressure record type does not guarantee export of readings
  originating in Samsung Health Monitor. Verify with a real watch/phone. A manual
  Health Connect record or a compatible cuff/source app can validate the pipeline.
- Guest accounts are suitable for a demo; use durable sign-in before relying on
  health history across devices or reinstalls.

## Verification

Implementation environment: Flutter/Dart SDK was unavailable (`flutter: command
not found`), so dependency resolution, compilation, and automated tests have not
been run. Manifest XML, Firebase JSON, and `git diff --check` were checked.

Run `flutter analyze`, `flutter test test/health_data/`, and
`flutter build apk --debug` after dependency resolution. On a real device, verify
permission denial/revocation, empty data, a paired reading, a source correction,
a source deletion, pause/resume, account switching, and cloud deletion. Observe
Firestore updates from a second client authenticated as the same user.

For release, provide the actual published privacy policy and complete Google
Play's health permission declarations. The native permission-rationale activity
currently explains the prototype's collection and deletion behaviour.
