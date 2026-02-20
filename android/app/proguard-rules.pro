# Flutter / Dart
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# SharedPreferences - keep so storage/prefs load in release
-keep class androidx.preference.** { *; }
-dontwarn androidx.preference.**

# Path provider / file access
-keep class io.flutter.plugins.pathprovider.** { *; }

# Sqflite / database
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }

# Prevent stripping of classes used by reflection (e.g. plugins)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# WebView / Chromium - ensure WebView loads 127.0.0.1 in release
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void *(android.webkit.WebView, java.lang.String);
}
-keep class android.webkit.** { *; }

# AndroidX Window / Sidecar - FlutterView WindowInfoTracker (avoid ClassNotFoundException on older devices)
-keep class androidx.window.sidecar.** { *; }
-keep class androidx.window.layout.** { *; }

# Cryptography / crypto plugins used by book decryption
-keep class androidx.security.crypto.** { *; }
-dontwarn javax.annotation.**

# cryptography_flutter - native AES-GCM, prevent stripping
-keep class dev.dint.cryptography_flutter.** { *; }
