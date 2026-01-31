package com.liqvid.tv_app_books

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telephony.TelephonyManager
import android.webkit.WebView
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.liqvid.tv_app_books/device_id"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getDeviceId") {
                result.success(getDeviceIdentifier())
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            WebView.setWebContentsDebuggingEnabled(true)
        } catch (e: Exception) { }
    }

    private fun getDeviceIdentifier(): String {
        // Try IMEI first (works on API 28 and below with READ_PHONE_STATE; restricted on API 29+)
        val imei = getImeiOrNull()
        if (!imei.isNullOrBlank()) {
            return "android_imei_$imei"
        }
        // Fallback: Android ID (always available, unique per app install)
        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        return if (androidId.isNotBlank()) "android_$androidId" else "android_unknown"
    }

    private fun getImeiOrNull(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: IMEI restricted for third-party apps
                null
            } else {
                val telephony = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                if (telephony != null && ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                    @Suppress("DEPRECATION")
                    telephony.deviceId?.takeIf { it.isNotBlank() }
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            null
        }
    }
}
