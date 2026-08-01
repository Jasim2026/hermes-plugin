# ============================================================
# Hermes Plugin — ProGuard/R8 Rules
# ============================================================

# ---- Shizuku (keep API classes, they're accessed via reflection) ----
-keep class rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }
-dontwarn rikka.shizuku.**

# ---- Flutter embedding (selective keep) ----
# Keep Flutter engine entry point and plugin registration
-keep class io.flutter.embedding.engine.FlutterEngine { *; }
-keep class io.flutter.embedding.engine.dart.DartExecutor { *; }
-keep class io.flutter.embedding.engine.dart.DartExecutor$DartEntrypoint { *; }
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class io.flutter.plugin.common.MethodChannel$Result { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep FlutterActivity and FlutterFragmentActivity
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }

# ---- AndroidX ----
-keep class androidx.core.app.** { *; }
-keep class androidx.core.content.ContextCompat { *; }

# ---- App classes (accessed via MethodChannel from Dart) ----
-keep class com.hermes.plugin.MainActivity { *; }
-keep class com.hermes.plugin.HermesAccessibilityService { *; }
-keep class com.hermes.plugin.HermesService { *; }
-keep class com.hermes.plugin.ShizukuServiceImpl { *; }

# ---- Remove logging in release ----
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# ---- Optimize ----
-optimizationpasses 5
-allowaccessmodification
-repackageclasses ''
