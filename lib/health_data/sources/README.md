# Sources

`blood_pressure_source.dart` exposes the read-only native Android Health Connect
bridge. The Kotlin implementation lives in `android/app/src/main/kotlin/com/example/hackathon/MainActivity.kt`.
It handles availability, user-initiated permission requests, and paginated paired
blood pressure records. No iOS provider is implemented.
