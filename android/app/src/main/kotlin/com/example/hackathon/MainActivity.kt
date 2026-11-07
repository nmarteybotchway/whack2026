package com.example.hackathon

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant

class MainActivity : FlutterFragmentActivity() {
    private val scope = MainScope()
    private val permission = HealthPermission.getReadPermission(BloodPressureRecord::class)
    private var pendingPermission: MethodChannel.Result? = null
    private val permissionLauncher = registerForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) { granted ->
        pendingPermission?.success(granted.contains(permission))
        pendingPermission = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                            result.success(HealthConnectClient.getOrCreate(this@MainActivity)
                                .permissionController.getGrantedPermissions().contains(permission))
                        } catch (error: Exception) {
                            result.error("permission_check", "Could not check health permission.", null)
                        }
                    }
                } else if (call.method == "requestPermission") {
                    if (pendingPermission != null) {
                        result.error("busy", "A permission request is already open.", null)
                    } else {
                        pendingPermission = result
                        permissionLauncher.launch(setOf(permission))
                    }
                } else if (call.method == "readBloodPressure") {
                    scope.launch {
                        try {
                            val client = HealthConnectClient.getOrCreate(this@MainActivity)
                            if (!client.permissionController.getGrantedPermissions().contains(permission)) {
                                result.error("permission", "Blood pressure read permission is required.", null)
                                return@launch
                            }
                            val start = Instant.ofEpochMilli(call.argument<Number>("start")!!.toLong())
                            val end = Instant.ofEpochMilli(call.argument<Number>("end")!!.toLong())
                            val records = mutableListOf<Map<String, Any?>>()
                            var token: String? = null
                            do {
                                val page = client.readRecords(ReadRecordsRequest(
                                    recordType = BloodPressureRecord::class,
                                    timeRangeFilter = TimeRangeFilter.between(start, end),
                                    pageToken = token
                                ))
                                records.addAll(page.records.map { record -> mapOf(
                                    "id" to record.metadata.id,
                                    "systolic" to record.systolic.inMillimetersOfMercury,
                                    "diastolic" to record.diastolic.inMillimetersOfMercury,
                                    "measuredAt" to record.time.toEpochMilli(),
                                    "sourceApp" to record.metadata.dataOrigin.packageName,
                                    "sourceModifiedAt" to record.metadata.lastModifiedTime.toEpochMilli(),
                                    "deviceManufacturer" to record.metadata.device?.manufacturer,
                                    "deviceModel" to record.metadata.device?.model
                                ) })
                                token = page.pageToken?.takeIf { it.isNotEmpty() }
                            } while (token != null)
                            result.success(records)
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
        scope.cancel()
        pendingPermission = null
        super.onDestroy()
    }
}
