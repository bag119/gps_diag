package com.gpsdiag.gps_diag

import android.content.Context
import android.location.GpsStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gpsdiag/gps_status"
    private lateinit var locationManager: LocationManager
    private val satelliteData = mutableListOf<Map<String, Any>>()
    private var locationData = mapOf<String, Any>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGpsStatus" -> {
                    try {
                        setupGpsListener()
                        result.success(getGpsData())
                    } catch (e: Exception) {
                        result.error("GPS_ERROR", e.message, null)
                    }
                }
                "isGpsEnabled" -> {
                    result.success(locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER))
                }
                "getLastLocation" -> {
                    try {
                        val location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        if (location != null) {
                            result.success(mapOf(
                                "latitude" to location.latitude,
                                "longitude" to location.longitude,
                                "altitude" to location.altitude,
                                "accuracy" to location.accuracy,
                                "speed" to location.speed,
                                "time" to location.time
                            ))
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("LOCATION_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupGpsListener() {
        satelliteData.clear()

        val gpsStatusListener = object : GpsStatus.Listener {
            override fun onGpsStatusChanged(event: Int) {
                when (event) {
                    GpsStatus.GPS_EVENT_SATELLITE_STATUS -> {
                        val gpsStatus = locationManager.getGpsStatus(null)
                        satelliteData.clear()
                        gpsStatus?.let { status ->
                            val satellites = status.satellites
                            satellites.forEach { satellite ->
                                satelliteData.add(mapOf(
                                    "prn" to satellite.prn,
                                    "snr" to satellite.snr,
                                    "elevation" to satellite.elevation,
                                    "azimuth" to satellite.azimuth,
                                    "used" to satellite.usedInFix()
                                ))
                            }
                        }
                    }
                }
            }
        }

        try {
            locationManager.addGpsStatusListener(gpsStatusListener)
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000,
                1f,
                object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        locationData = mapOf(
                            "latitude" to location.latitude,
                            "longitude" to location.longitude,
                            "altitude" to location.altitude,
                            "accuracy" to location.accuracy,
                            "speed" to location.speed,
                            "bearing" to location.bearing,
                            "time" to location.time
                        )
                    }

                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                }
            )
        } catch (e: SecurityException) {
            // 权限未授予
        }
    }

    private fun getGpsData(): Map<String, Any> {
        return mapOf(
            "satellites" to satelliteData.toList(),
            "location" to locationData
        )
    }
}
