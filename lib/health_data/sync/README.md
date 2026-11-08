# Sync

`blood_pressure_sync.dart` reconciles a rolling 29-day Health Connect window into
`users/{uid}/bloodPressure/{sourceRecordId}`. It uploads changes, removes deleted
records within that window, and checks account identity before each write batch.
`HealthTrackingController` (owned by `HomePage`) handles foreground refresh
scheduling and explicit upload consent.
See the parent README for setup, limitations, and deletion behaviour.
