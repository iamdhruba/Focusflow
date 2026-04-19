import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/core/services/native_channel_service.dart';

// ── Permission State ──────────────────────────────────────────────────────────

class PermissionState {
  final bool usageStats;
  final bool accessibility;
  final bool overlay;
  final bool deviceAdmin;
  final bool batteryOptimization;
  final bool isChecking;

  const PermissionState({
    this.usageStats = false,
    this.accessibility = false,
    this.overlay = false,
    this.deviceAdmin = false,
    this.batteryOptimization = false,
    this.isChecking = false,
  });

  bool get allGranted => usageStats && accessibility && overlay && deviceAdmin && batteryOptimization;
  int get grantedCount =>
      [usageStats, accessibility, overlay, deviceAdmin, batteryOptimization].where((e) => e).length;

  PermissionState copyWith({
    bool? usageStats,
    bool? accessibility,
    bool? overlay,
    bool? deviceAdmin,
    bool? batteryOptimization,
    bool? isChecking,
  }) =>
      PermissionState(
        usageStats: usageStats ?? this.usageStats,
        accessibility: accessibility ?? this.accessibility,
        overlay: overlay ?? this.overlay,
        deviceAdmin: deviceAdmin ?? this.deviceAdmin,
        batteryOptimization: batteryOptimization ?? this.batteryOptimization,
        isChecking: isChecking ?? this.isChecking,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PermissionNotifier extends StateNotifier<PermissionState> {
  PermissionNotifier() : super(const PermissionState());

  final _native = NativeChannelService();

  Future<void> checkAll() async {
    state = state.copyWith(isChecking: true);
    final results = await Future.wait([
      _native.hasUsageStatsPermission(),
      _native.hasAccessibilityPermission(),
      _native.hasOverlayPermission(),
      _native.isDeviceAdminActive(),
      _native.isIgnoringBatteryOptimizations(),
    ]);
    state = PermissionState(
      usageStats: results[0],
      accessibility: results[1],
      overlay: results[2],
      deviceAdmin: results[3],
      batteryOptimization: results[4],
      isChecking: false,
    );
  }

  Future<void> requestUsageStats() => _native.openUsageStatsSettings();
  Future<void> requestAccessibility() => _native.openAccessibilitySettings();
  Future<void> requestOverlay() => _native.openOverlaySettings();
  Future<void> requestDeviceAdmin() => _native.requestDeviceAdmin();
  Future<void> requestBatteryOptimization() => _native.openBatteryOptimizationSettings();
}

final permissionProvider =
    StateNotifierProvider<PermissionNotifier, PermissionState>(
  (ref) => PermissionNotifier(),
);
