import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/api_constants.dart';

/// Bridge to the native Android Kotlin layer via MethodChannels.
/// Provides typed Dart wrappers for all native capabilities.
class NativeChannelService {
  NativeChannelService._internal();
  static final NativeChannelService _instance = NativeChannelService._internal();
  factory NativeChannelService() => _instance;

  static const _usageChannel = MethodChannel(ApiConstants.usageStatsChannel);
  static const _permChannel = MethodChannel(ApiConstants.permissionChannel);
  static const _blockChannel = MethodChannel(ApiConstants.blockingChannel);

  // ─── Usage Stats ─────────────────────────────────────────────────────────

  /// Returns a map of { packageName: usedMs } for today (since midnight).
  Future<Map<String, int>> getTodayUsageStats() async {
    if (kIsWeb) return {};
    try {
      final result = await _usageChannel.invokeMethod<Map>('getTodayUsage');
      return result?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? {};
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
    } on PlatformException catch (e) {
      debugPrint('getInstalledApps error: ${e.message}');
      return [];
    }
  }

  // ─── Permissions ──────────────────────────────────────────────────────────

  Future<bool> hasUsageStatsPermission() async {
    if (kIsWeb) return true; // Mock true for web demo
    try {
      return await _permChannel.invokeMethod<bool>('hasUsageStatsPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openUsageStatsSettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openUsageStatsSettings');
    } on PlatformException catch (e) {
      debugPrint('openUsageStatsSettings error: ${e.message}');
    }
  }

  Future<bool> hasAccessibilityPermission() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      debugPrint('openAccessibilitySettings error: ${e.message}');
    }
  }

  Future<bool> hasOverlayPermission() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openOverlaySettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openOverlaySettings');
    } on PlatformException catch (e) {
      debugPrint('openOverlaySettings error: ${e.message}');
    }
  }

  Future<bool> isDeviceAdminActive() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('isDeviceAdminActive') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestDeviceAdmin() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('requestDeviceAdmin');
    } on PlatformException catch (e) {
      debugPrint('requestDeviceAdmin error: ${e.message}');
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb) return true;
    try {
      return await _permChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (kIsWeb) return;
    try {
      await _permChannel.invokeMethod('openBatteryOptimizationSettings');
    } on PlatformException catch (e) {
      debugPrint('openBatteryOptimizationSettings error: ${e.message}');
    }
  }

  // ─── Blocking Engine ──────────────────────────────────────────────────────

  /// Push updated blocking rules to native layer (Room DB).
  Future<void> updateBlockingRules(List<Map<String, dynamic>> policies) async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('updateBlockingRules', {'policies': policies});
    } on PlatformException catch (e) {
      debugPrint('updateBlockingRules error: ${e.message}');
    }
  }

  /// Start foreground tracking service.
  Future<void> startForegroundService() async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('startForegroundService');
    } on PlatformException catch (e) {
      debugPrint('startForegroundService error: ${e.message}');
    }
  }

  /// Stop foreground tracking service.
  Future<void> stopForegroundService() async {
    if (kIsWeb) return;
    try {
      await _blockChannel.invokeMethod('stopForegroundService');
    } on PlatformException catch (e) {
      debugPrint('stopForegroundService error: ${e.message}');
    }
  }
}
