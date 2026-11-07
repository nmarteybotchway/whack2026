# Sources

`blood_pressure_source.dart` exposes the read-only native Android Health Connect
bridge. The Kotlin implementation lives in `android/app/src/main/kotlin/com/example/hackathon/MainActivity.kt`.
It handles availability, user-initiated permission requests (one request for
blood pressure, heart rate, steps, sleep and weight), per-user tracking settings,
and paginated reads of paired blood pressure (`read`), heart rate, steps, sleep
and weight records. No iOS provider is implemented.
