package com.liqvid.tv_app_books

import android.os.Bundle
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable file access in WebView for external storage
        // This allows WebView to access files on external storage (USB drives, etc.)
        try {
            WebView.setWebContentsDebuggingEnabled(true)
            // Note: File access is enabled by default in WebView, but we need
            // proper permissions in AndroidManifest.xml which are already added
        } catch (e: Exception) {
            // Ignore if WebView is not available
        }
    }
}
