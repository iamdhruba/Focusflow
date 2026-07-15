import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/api_constants.dart';

/// Bridge to the native Android Kotlin layer via MethodChannels.
/// Provides typed Dart wrappers for all native capabilities.
///
/// Stability notes (2025):
///   * Every MethodChannel call now catches `MissingPluginException` first
///     (Fix 7) before `PlatformException`. Some older Flutter SDKs and
///     certain emulator installs surface MissingPluginException as its
///     own type, separate from PlatformException.
///   * `getInitialBlockedApp()` (Fix 4) lets Dart pull the package name
///     that triggered a cold-launch blocked-app intent, so we recover
///     from the race where Kotlin's `channel.invokeMethod("onAppBlocked")`
///     fires before Dart's `addPostFrameCallback` listener is attached.
class NativeChannelService {
  NativeChannelService._internal();
  static final NativeChannelService _instance = NativeChannelService._internal();
  factory NativeChannelService() => _instance;

  static const _usageChannel = MethodChannel(ApiConstants.usageStatsChannel);
  static const _permChannel = MethodChannel(ApiConstants.permissionChannel);
  static const _blockChannel = MethodChannel(ApiConstants.blockingChannel);

  void init({
    Function(Map<String, dynamic>)? onAppBlocked,
    Function(Map<String, dynamic>)? onScreenUsageUpdate,
  }) {
    _blockChannel.setMethodCallHandler((call) async {
      final raw = call.arguments;
      final args = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (call.method == 'onAppBlocked' && onAppBlocked != null) {
        onAppBlocked(args);
      } else if (call.method == 'onScreenUsageUpdate' && onScreenUsageUpdate != null) {
        onScreenUsageUpdate(args);
      }
    });
  }

  // ─── Usage Stats ─────────────────────────────────────────────────────────

  /// Returns a map of { packageName: usedMs } for today (since midnight).
  Future<Map<String, int>> getTodayUsageStats() async {
    if (kIsWeb) return {};
    try {
      final result = await _usageChannel.invokeMethod<Map>('getTodayUsage');
      return result?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? {};
    } on MissingPluginException {
      debugPrint('getTodayUsage: missing plugin (no native handler)');
      return {};
    } on PlatformException catch (e) {
      debugPrint('getTodayUsage error: ${e.message}');
      return {};
    }
  }

  /// Returns list of installed apps as [{packageName, appName, icon (base64)}]
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    if (kIsWeb) return [];
    try {
      final result = await _usageChannel.invokeMethod<List>('getInstalledApps');
      return result
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
    } on MissingPluginException {
      debugPrint('getInstalledApps: missing plugin (no native handler)');
      return [];
    } on PlatformException catch (e) {
      debugPrint('getInstalledApps error: ${e.message}');
      return [];
    }
  }

  /// Returns icon for a specific package as base64.
  Future<String?> getAppIcon(String packageName) async {
    if (kIsWeb) return null;
    try {
      return await _usageChannel.invokeMethod<String>('getAppIcon', {'packageName': packageName});
    } on MissingPluginException {
      debugPrint('getAppIcon: missing plugin (no native handler)');
      return null;
    } on PlatformException catch (e) {
      debugPrint('getAppIcon error: ${e.message}');
      return null;
    }
  }

  Future<int> getBlockedAttempts() async {
    if (kIsWeb) return 0;
    try {
      return await _usageChannel.invokeMethod<int>('getBlockedAttempts') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<int> getPhonePickups() async {
    if (kIsWeb) return 0;
    try {
      return await _usageChannel.invokeMethod<int>('getPhonePickups') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  // ─── Permissions ──────────────────────────────────────────────────────────

  Future<bool> hasUsageStatsPermission() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('hasUsageStatsPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openUsageStatsSettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openUsageStatsSettings');
    } on MissingPluginException catch (_) {
      debugPrint('openUsageStatsSettings: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('openUsageStatsSettings error: ${e.message}');
    }
  }

  Future<bool> hasAccessibilityPermission() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openAccessibilitySettings');
    } on MissingPluginException catch (_) {
      debugPrint('openAccessibilitySettings: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('openAccessibilitySettings error: ${e.message}');
    }
  }

  Future<bool> hasOverlayPermission() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openOverlaySettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openOverlaySettings');
    } on MissingPluginException catch (_) {
      debugPrint('openOverlaySettings: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('openOverlaySettings error: ${e.message}');
    }
  }

  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openAppSettings');
    } on MissingPluginException catch (_) {
      debugPrint('openAppSettings: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('openAppSettings error: ${e.message}');
    }
  }

  Future<bool> isDeviceAdminActive() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('isDeviceAdminActive') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestDeviceAdmin() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('requestDeviceAdmin');
    } on MissingPluginException catch (_) {
      debugPrint('requestDeviceAdmin: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('requestDeviceAdmin error: ${e.message}');
    }
  }

  Future<void> setUninstallBlocked(bool blocked) async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('setUninstallBlocked', {'blocked': blocked});
    } on MissingPluginException catch (_) {
      debugPrint('setUninstallBlocked: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('setUninstallBlocked error: ${e.message}');
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openBatteryOptimizationSettings');
    } on MissingPluginException catch (_) {
      debugPrint('openBatteryOptimizationSettings: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('openBatteryOptimizationSettings error: ${e.message}');
    }
  }

  Future<void> setSafeMode(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('setSafeMode', {'enabled': enabled});
    } on MissingPluginException catch (_) {
      debugPrint('setSafeMode: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('setSafeMode error: ${e.message}');
    }
  }

  Future<bool> hasNotificationPermission() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('hasNotificationPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestNotificationPermission() async {
    if (kIsWeb) return;
    try {
      final granted = await _permChannel.invokeMethod<bool>('requestNotificationPermission');
      debugPrint('requestNotificationPermission result: $granted');
    } on MissingPluginException catch (_) {
      debugPrint('requestNotificationPermission: missing plugin');
    } on PlatformException catch (e) {
      debugPrint('requestNotificationPermission error: ${e.message}');
    }
  }

  // ─── Blocking Engine ──────────────────────────────────────────────────────

  Future<bool> getStrictModeStatus() async {
    if (kIsWeb) return false;
    try {
      return await _blockChannel.invokeMethod<bool>('getStrictModeStatus') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> updateStrictMode({required bool enabled, String? pin}) async {
    if (kIsWeb) return true;
    try {
      return await _blockChannel.invokeMethod<bool>('updateStrictMode', {
            'enabled': enabled,
            'pin': pin,
          }) ??
          false;
    } on MissingPluginException catch (_) {
      debugPrint('updateStrictMode: missing plugin');
      return false;
    } on PlatformException catch (e) {
      debugPrint('updateStrictMode error: ${e.message}');
      return false;
    }
  }

  // Push updated blocking rules to the native layer (SharedPreferences-backed
  // rule table consumed by FocusAccessibilityService).
  Future<void> updateBlockingRules(List<Map<String, dynamic>> policies) async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('updateBlockingRules', {'policies': policies});
    } on MissingPluginException catch (_) {
      debugPrint('updateBlockingRules: missing plugin (native side has no handler)');
    } on PlatformException catch (e) {
      debugPrint('updateBlockingRules error: ${e.message}');
    }
  }

  // Phase 3: push per-screen rules (e.g. block Instagram Reels). Each map:
  // { packageName, screenKey, timeLimitMinutes, isActive }. Consumed by
  // MainActivity.kt's `updateScreenBlockingRules` handler which writes
  // FocusFlowScreenRules SharedPreferences. FocusAccessibilityService
  // checks this table on every walker hit.
  Future<void> updateScreenBlockingRules(List<Map<String, dynamic>> rules) async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('updateScreenBlockingRules', {'rules': rules});
    } on MissingPluginException catch (_) {
      debugPrint('updateScreenBlockingRules: missing plugin (no native handler)');
    } on PlatformException catch (e) {
      debugPrint('updateScreenBlockingRules error: ${e.message}');
    }
  }

  // Fix 4: pull the cached blocked-package so we can recover from the cold-
  // launch race where the native side invoked onAppBlocked before Dart's
  // listener was attached. Returns null if no cold-launch package is queued.
  Future<String?> getInitialBlockedApp() async {
    if (kIsWeb) return null;
    try {
      return await _blockChannel.invokeMethod<String>('getInitialBlockedApp');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('getInitialBlockedApp error: ${e.message}');
      return null;
    }
  }

  // Phase 1: per-screen block key (e.g. "reels", "fyp"). Null if the launch
  // was triggered by an app-level (not screen-level) block.
  Future<String?> getInitialBlockedScreen() async {
    if (kIsWeb) return null;
    try {
      return await _blockChannel.invokeMethod<String>('getInitialBlockedScreen');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('getInitialBlockedScreen error: ${e.message}');
      return null;
    }
  }

  // Phase 1: human-friendly name for the blocked screen (e.g. "Reels", "For You").
  Future<String?> getInitialBlockedScreenFriendly() async {
    if (kIsWeb) return null;
    try {
      return await _blockChannel.invokeMethod<String>('getInitialBlockedScreenFriendly');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('getInitialBlockedScreenFriendly error: ${e.message}');
      return null;
    }
  }

  /// Start foreground tracking service.
  Future<void> startForegroundService() async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('startForegroundService');
    } on MissingPluginException catch (_) {
      debugPrint('startForegroundService: missing plugin (not implemented in native)');
    } on PlatformException catch (e) {
      debugPrint('startForegroundService error: ${e.message}');
    }
  }

  /// Stop foreground tracking service.
  Future<void> stopForegroundService() async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('stopForegroundService');
    } on MissingPluginException catch (_) {
      debugPrint('stopForegroundService: missing plugin (not implemented in native)');
    } on PlatformException catch (e) {
      debugPrint('stopForegroundService error: ${e.message}');
    }
  }

  /// Phase 4: pull today's per-screen dwell totals from native SharedPreferences.
  /// Returns a list of {packageName, screenKey, usedMs} maps. Used on cold
  /// launch + on every `load()` to merge the live application state with
  /// the persisted record (the live channel only fires while Flutter is
  /// foregrounded, so this is how the UI stays honest after a restart).
  Future<List<Map<String, dynamic>>> getScreenUsageTotals() async {
    if (kIsWeb) return [];
    try {
      final result = await _blockChannel.invokeMethod<List>('getScreenUsageTotals');
      return result
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
    } on MissingPluginException {
      return [];
    } on PlatformException catch (e) {
      debugPrint('getScreenUsageTotals error: ${e.message}');
      return [];
    }
  }
}
