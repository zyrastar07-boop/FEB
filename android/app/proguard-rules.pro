# Suppress missing class warnings for Play Core deferred component references in Flutter Engine
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-keep class com.google.android.play.core.** { *; }

# Preserve Flutter engine, platform channel classes, and plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.header.** { *; }
-keep class io.flutter.userrequested.** { *; }

# Firebase & Google Play Services protection
-dontwarn com.google.android.gms.**
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }

# Retain generic type signatures and annotations for JSON serialization and reflection
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod