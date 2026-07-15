# ─── FocusFlow ProGuard / R8 Rules ─────────────────────────────────────────
# Historical: this file kept ONLY `io.flutter.**`, which works for the Flutter
# engine itself but strips any plugin that uses reflection, has native bindings
# via MethodChannel, or registers via @Keep / annotation processing. As of
# v1.0.0 we ship with `isMinifyEnabled = false` for safety, but every plugin
# keep rule is written here as defense-in-depth so a future 1.0.1 release can
# flip R8 back on WITHOUT having to re-validate each plugin individually.
#
# Authoring rule: when adding a new plugin, search its readme for "proguard"
# or "r8" — most maintained plugins ship a snippet. If absent, prefer
# `-keep class <plugin.dotted.package>.** { *; }` over a conservative default.
# Avoid `-keep class **.** { *; }` — it nullifies the point of R8.

# ─── Flutter engine core ────────────────────────────────────────────────────
# Safe baseline — Flutter docs call these out explicitly.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ─── flutter_foreground_task ───────────────────────────────────────────────
# Uses reflection on Dart isolate entry-points in the pravera package.
# Note: every keep rule below uses the maximally broad `** { *; }` pattern
# on purpose for v1.0.0 defense-in-depth. v1.0.1+ can tighten each rule
# as the project gains per-plugin R8 validation data.
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# ─── workmanager ────────────────────────────────────────────────────────────
# @pragma('vm:entry-point') callback dispatcher reflection + AndroidX Work.
-keep class androidx.work.** { *; }
-keep class com.fluttercommunity.workmanager.** { *; }
-dontwarn androidx.work.**

# ─── flutter_secure_storage ─────────────────────────────────────────────────
# EncryptedSharedPreferences uses Tink under the hood; reflection in the
# secure-storage plugin reads Android Keystore keys by class name.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**
-dontwarn com.google.crypto.tink.**

# ─── permission_handler ─────────────────────────────────────────────────────
# Plugin enumerates Android permissions by reflection on Build.VERSION
# constants and registers handler classes by AndroidX name.
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ─── connectivity_plus ──────────────────────────────────────────────────────
# Reads ConnectivityManager callbacks via reflection on hidden APIs that
# change per Android version.
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-dontwarn dev.fluttercommunity.plus.connectivity.**

# ─── url_launcher ───────────────────────────────────────────────────────────
# Inspects Android intent filter metadata via reflection.
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# ─── cached_network_image ───────────────────────────────────────────────────
# Loads cache keys via reflection on FlutterImageManager.
-keep class com.github.xunweigong.cached_network_image.** { *; }
-dontwarn com.github.xunweigong.cached_network_image.**

# ─── lottie ─────────────────────────────────────────────────────────────────
# Airbnb lottie uses annotation-processor-generated classes for property
# binding; stripping any of them breaks JSON-driven animations.
-keep class com.airbnb.lottie.** { *; }
-dontwarn com.airbnb.lottie.**

# ─── google_fonts ───────────────────────────────────────────────────────────
# Pure-Dart runtime but loads font assets via Flutter asset bundle; R8
# shouldn't strip asset metadata. Just-in-case for any future
# platform-channel hooks.
-keep class io.flutter.plugins.googlefonts.** { *; }
-dontwarn io.flutter.plugins.googlefonts.**

# ─── flutter_svg ────────────────────────────────────────────────────────────
# Dart-side, but `flutter_svg` v2 uses dart-only paths. No native keep
# needed. Listed here for inventory completeness.
# FUTURE: if a later `flutter_svg` version adds native bindings (e.g.
# a JNI bridge for complex-SVG parsing, which is a known perf
# bottleneck in the current pure-Dart 2.x parser), this section needs
# a keep rule matching the new package — the actual package is
# unknown until a native version ships, so don't hardcode a guess here.

# ─── Other pure-Dart plugins (no R8 keep needed) ────────────────────────────
# Listed for completeness so future maintainers don't search for a rule
# that intentionally does not exist:
#   • flutter_dotenv       — dart-only asset loader
#   • go_router           — dart-only navigator
#   • flutter_riverpod    — dart-only state mgmt
#   • dio                 — dart-only HTTP
#   • intl                — dart-only i18n
#   • uuid                — dart-only ID generator
#   • shimmer             — dart-only animation
#   • cupertino_icons     — asset bundle (Flutter keeps by default)

# ─── sqflite (native plugin) ────────────────────────────────────────────────
# The current `sqflite` package (2.x) routes through AndroidX
# `androidx.sqlite.db.framework`; the native `libsqflite.so` is C/C++
# so R8 never touches it. Keep the AndroidX package so its support
# classes (e.g. SupportSQLiteOpenHelper callbacks) aren't stripped.
# `sqflite_common_ffi` devDep is irrelevant to release builds.
# Intentional duplication of AndroidX's own consumer rules. Both
# paths are listed so a future maintainer can re-validate the dup:
#   • source-tree: `sqlite/sqlite-framework/src/main/resources/
#     META-INF/proguard/framework-proguard.txt` in the AndroidX
#     monorepo
#   • AAR-shipped: `META-INF/proguard/framework-proguard.txt` inside
#     the published androidx.sqlite.db.framework artifact
# Belt-and-suspenders so a future AndroidX refactor that loosens its
# consumer rules can't silently strip these classes from our APK.
-keep class androidx.sqlite.db.** { *; }
-dontwarn androidx.sqlite.db.**

# ─── shared_preferences ─────────────────────────────────────────────────────
# Pure plugin-channel but AndroidX SharedPreferencesAsync uses
# androidx.content-resolver reflection.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ─── Standard Android desugaring realities ──────────────────────────────────
# If we ever turn on `coreLibraryDesugaring`, add:
#   -keep class j$.** { *; }
#   -dontwarn j$.**
# — currently OFF, listed here for the future handoff.
