package com.gpsdiag.gps_diag

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.GpsStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gpsdiag/gps_status"
    private lateinit var locationManager: LocationManager
    
    private var satellites: MutableList<Map<String, Any>> = mutableListOf()
    private var locationData: MutableMap<String, Any> = mutableMapOf()
    private var gpsEnabled: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGpsStatus" -> {
                    try {
                        result.success(getGpsData())
                    } catch (e: Exception) {
                        result.error("GPS_ERROR", e.message, null)
                    }
                }
                "isGpsEnabled" -> {
                    gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    result.success(gpsEnabled)
                }
                "requestLocationUpdate" -> {
                    try {
                        startLocationUpdates()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("GPS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startLocationUpdates() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            return
        }

        // 清理旧数据
        satellites.clear()
        locationData.clear()

        // 注册GPS状态监听器
        val gpsStatusListener = GpsStatus.Listener { event ->
            when (event) {
                GpsStatus.GPS_EVENT_SATELLITE_STATUS -> {
                    val gpsStatus = locationManager.getGpsStatus(null)
                    satellites.clear()
                    gpsStatus?.let { status ->
                        status.satellites?.iterator()?.forEach { sat ->
                            satellites.add(mapOf(
                                "prn" to sat.prn,
                                "snr" to (sat.snr ?: 0.0),
                                "elevation" to (sat.elevation ?: 0.0),
                                "azimuth" to (sat.azimuth ?: 0.0),
                                "used" to sat.usedInFix()
                            ))
                        }
                    }
                }
                GpsStatus.GPS_EVENT_STARTED -> {
                    gpsEnabled = true
                }
                GpsStatus.GPS_EVENT_STOPPED -> {
                    gpsEnabled = false
                }
            }
        }

        try {
            locationManager.addGpsStatusListener(gpsStatusListener)
        } catch (e: Exception) {
            // ignore
        }

        // 请求位置更新
        val locationListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                locationData = mutableMapOf(
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "altitude" to location.altitude,
                    "accuracy" to location.accuracy,
                    "speed" to location.speed.toDouble(),
                    "bearing" to location.bearing.toDouble(),
                    "time" to location.time
                )
            }

            override fun onProviderEnabled(provider: String) {
                if (provider == LocationManager.GPS_PROVIDER) {
                    gpsEnabled = true
                }
            }

            override fun onProviderDisabled(provider: String) {
                if (provider == LocationManager.GPS_PROVIDER) {
                    gpsEnabled = false
                }
            }

            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }

        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000,
                0f,
                locationListener,
                Looper.getMainLooper()
            )
        } catch (e: Exception) {
            // ignore
        }

        // 检查初始状态
        gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private fun getGpsData(): Map<String, Any> {
        return mapOf(
            "satellites" to satellites.toList(),
            "location" to locationData.toMap(),
            "gpsEnabled" to gpsEnabled
        )
    }
}
