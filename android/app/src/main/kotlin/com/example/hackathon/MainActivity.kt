package com.example.hackathon

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant

class MainActivity : FlutterFragmentActivity() {
    private val scope = MainScope()
    private lateinit var duplexSpeechBridge: DuplexSpeechBridge
    private lateinit var liveVoiceBridge: LiveVoiceBridge

    // Read permissions for every record type the app can pull from Health
    // Connect (Samsung Health syncs these automatically).
    private val permissions = setOf(
        HealthPermission.getReadPermission(BloodPressureRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
    )
    private var pendingPermission: MethodChannel.Result? = null
    private val permissionLauncher = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        pendingPermission?.success(granted.isNotEmpty())
        pendingPermission = null
    }

    /** Reads one Health Connect record type over the requested time window. */
    private suspend inline fun <reified T : Record> readRecords(
        call: MethodCall,
        toMap: (T) -> Map<String, Any?>
    ): List<Map<String, Any?>> {
        val client = HealthConnectClient.getOrCreate(this)
        if (!client.permissionController.getGrantedPermissions()
                .contains(HealthPermission.getReadPermission(T::class))) {
            throw SecurityException("Missing read permission for ${T::class.simpleName}")
        }
        val start = Instant.ofEpochMilli(call.argument<Number>("start")!!.toLong())
        val end = Instant.ofEpochMilli(call.argument<Number>("end")!!.toLong())
        val records = mutableListOf<Map<String, Any?>>()
        var token: String? = null
        do {
            val page = client.readRecords(ReadRecordsRequest(
                recordType = T::class,
                timeRangeFilter = TimeRangeFilter.between(start, end),
                pageToken = token
            ))
            records.addAll(page.records.map(toMap))
            token = page.pageToken?.takeIf { it.isNotEmpty() }
        } while (token != null)
        return records
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        duplexSpeechBridge = DuplexSpeechBridge(this)
        liveVoiceBridge = LiveVoiceBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DuplexSpeechBridge.METHOD_CHANNEL)
            .setMethodCallHandler(duplexSpeechBridge)
        io.flutter.plugin.common.EventChannel(flutterEngine.dartExecutor.binaryMessenger, DuplexSpeechBridge.EVENT_CHANNEL)
            .setStreamHandler(duplexSpeechBridge)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LiveVoiceBridge.METHOD_CHANNEL)
            .setMethodCallHandler(liveVoiceBridge)
        io.flutter.plugin.common.EventChannel(flutterEngine.dartExecutor.binaryMessenger, LiveVoiceBridge.EVENT_CHANNEL)
            .setStreamHandler(liveVoiceBridge)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sentinel/health_connect")
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences("sentinel_health", MODE_PRIVATE)
                if (call.method == "trackingSettings") {
                    val uid = call.argument<String>("userId") ?: ""
                    result.success(mapOf(
                        "introSeen" to preferences.getBoolean("introSeen", false),
                        "enabled" to preferences.getBoolean("enabled:$uid", false)
                    ))
                    return@setMethodCallHandler
                }
                if (call.method == "saveTrackingSettings") {
                    val uid = call.argument<String>("userId") ?: ""
                    val editor = preferences.edit()
                    call.argument<Boolean>("introSeen")?.let { editor.putBoolean("introSeen", it) }
                    call.argument<Boolean>("enabled")?.let { editor.putBoolean("enabled:$uid", it) }
                    if (editor.commit()) result.success(null)
                    else result.error("settings_failed", "Could not save health preferences.", null)
                    return@setMethodCallHandler
                }
                val status = HealthConnectClient.getSdkStatus(this)
                if (call.method == "availability") {
                    result.success(when (status) {
                        HealthConnectClient.SDK_AVAILABLE -> "available"
                        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "updateRequired"
                        else -> "unavailable"
                    })
                } else if (status != HealthConnectClient.SDK_AVAILABLE) {
                    result.error("unavailable", "Install or update Health Connect on a supported Android phone.", null)
                } else if (call.method == "hasPermission") {
                    scope.launch {
                        try {
                            val granted = HealthConnectClient.getOrCreate(this@MainActivity)
                                .permissionController.getGrantedPermissions()
                            // True when at least one requested record type is
                            // readable; per-type checks happen at read time.
                            result.success(granted.intersect(permissions).isNotEmpty())
                        } catch (error: Exception) {
                            result.error("permission_check", "Could not check health permission.", null)
                        }
                    }
                } else if (call.method == "requestPermission") {
                    if (pendingPermission != null) {
                        result.error("busy", "A permission request is already open.", null)
                    } else {
                        pendingPermission = result
                        permissionLauncher.launch(permissions)
                    }
                } else if (call.method == "readHeartRate") {
                    scope.launch {
                        try {
                            readRecords<HeartRateRecord>(call) { record ->
                                mapOf(
                                    "id" to record.metadata.id,
                                    // Samples within one session; bpm values.
                                    "bpmSamples" to record.samples.map { it.beatsPerMinute },
                                    "measuredAt" to record.startTime.toEpochMilli(),
                                    "endTime" to record.endTime.toEpochMilli(),
                                    "sourceApp" to record.metadata.dataOrigin.packageName
                                )
                            }.let(result::success)
                        } catch (error: Exception) {
                            result.error("read_failed", "Could not read heart rate: ${error.message}", null)
                        }
                    }
                } else if (call.method == "readSteps") {
                    scope.launch {
                        try {
                            readRecords<StepsRecord>(call) { record ->
                                mapOf(
                                    "id" to record.metadata.id,
                                    "count" to record.count,
                                    "measuredAt" to record.startTime.toEpochMilli(),
                                    "endTime" to record.endTime.toEpochMilli(),
                                    "sourceApp" to record.metadata.dataOrigin.packageName
                                )
                            }.let(result::success)
                        } catch (error: Exception) {
                            result.error("read_failed", "Could not read steps: ${error.message}", null)
                        }
                    }
                } else if (call.method == "readSleep") {
                    scope.launch {
                        try {
                            readRecords<SleepSessionRecord>(call) { record ->
                                mapOf(
                                    "id" to record.metadata.id,
                                    "measuredAt" to record.startTime.toEpochMilli(),
                                    "endTime" to record.endTime.toEpochMilli(),
                                    "durationMinutes" to java.time.Duration.between(record.startTime, record.endTime).toMinutes(),
                                    "sourceApp" to record.metadata.dataOrigin.packageName
                                )
                            }.let(result::success)
                        } catch (error: Exception) {
                            result.error("read_failed", "Could not read sleep sessions.", null)
                        }
                    }
                } else if (call.method == "readWeight") {
                    scope.launch {
                        try {
                            readRecords<WeightRecord>(call) { record ->
                                mapOf(
                                    "id" to record.metadata.id,
                                    "weightKg" to record.weight.inKilograms,
                                    "measuredAt" to record.time.toEpochMilli(),
                                    "sourceApp" to record.metadata.dataOrigin.packageName
                                )
                            }.let(result::success)
                        } catch (error: Exception) {
                            result.error("read_failed", "Could not read weight.", null)
                        }
                    }
                } else if (call.method == "readBloodPressure") {
                    scope.launch {
                        try {
                            result.success(readRecords<BloodPressureRecord>(call) { record -> mapOf(
                                "id" to record.metadata.id,
                                "systolic" to record.systolic.inMillimetersOfMercury,
                                "diastolic" to record.diastolic.inMillimetersOfMercury,
                                "measuredAt" to record.time.toEpochMilli(),
                                "sourceApp" to record.metadata.dataOrigin.packageName,
                                "sourceModifiedAt" to record.metadata.lastModifiedTime.toEpochMilli(),
                                "deviceManufacturer" to record.metadata.device?.manufacturer,
                                "deviceModel" to record.metadata.device?.model
                            ) })
                        } catch (error: Exception) {
                            result.error("read_failed", "Could not read blood pressure. Check Health Connect permissions and try again.", null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (::duplexSpeechBridge.isInitialized) duplexSpeechBridge.stop()
        if (::liveVoiceBridge.isInitialized) liveVoiceBridge.onMethodCall(MethodCall("dispose", null), object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
            override fun notImplemented() {}
        })
        scope.cancel()
        pendingPermission = null
        super.onDestroy()
    }

    override fun onStop() {
        // This feature is foreground-only; do not keep the microphone open while
        // the app is backgrounded or the screen is covered by another activity.
        if (::duplexSpeechBridge.isInitialized) duplexSpeechBridge.stop(notify = true)
        super.onStop()
    }
}
