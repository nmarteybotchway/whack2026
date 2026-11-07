# Health data collection

Scaffold for collecting health records in the Flutter phone app, initially from
Android Health Connect. No collection, permissions, storage, or uploads are
implemented yet.

## Structure

- `models/`: application-owned measurement and session types.
- `sources/`: Health Connect availability, permissions, and record access.
- `repositories/`: local persistence and queries for latest readings and history.
- `sync/`: incremental collection and optional Firebase uploads.

Intended flow:

```text
Health Connect -> source -> repository -> Flutter UI
                               |
                               v
                         Firebase sync
```

Watch data reaches Health Connect through its manufacturer's app. Collection here
reads the latest available records; it does not establish a live watch connection
or force the watch to sync.

## Implementation notes

- Keep platform/plugin calls inside `sources/`.
- Preserve source record IDs, source application, units, measurement intervals,
  and collection timestamps. Preserve device metadata when supplied.
- Represent permission denied, unsupported, no data, and stale data separately.
- Process updates and deletions as well as newly inserted records.
- Keep collection and cloud sharing explicitly user-controlled.
- Store all cloud records beneath `users/{uid}/`, following the repository's
  Firebase data layout. Suggested collections are `healthLatest`,
  `healthMeasurements`, and `healthSyncState`.
- Clear user-specific state when accounts change; never upload one user's
  queued records under another user's UID.

Start by implementing the Health Connect source and confirming available metrics
on a real phone/watch before adding background collection or cloud uploads.
