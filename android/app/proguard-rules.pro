# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core (deferred components / split install) — Flutter's embedding
# references these classes, but the app doesn't use deferred components, so they
# aren't on the classpath. Suppress R8's "missing class" errors for them.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Prevent obfuscation of certain classes if needed
# -keep class com.upendrapandey.school_app.models.** { *; }
