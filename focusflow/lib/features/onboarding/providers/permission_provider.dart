import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/core/services/native_channel_service.dart';

// ── Permission State ──────────────────────────────────────────────────────────

class PermissionState {
  final bool usageStats;
  final bool accessibility;
  final bool overlay;
  final bool deviceAdmin;
  final bool batteryOptimization;
  final bool notifications;
  final bool isChecking;

  const PermissionState({
    this.usageStats = false,
    this.accessibility = false,
    this.overlay = false,
    this.deviceAdmin = false,
    this.batteryOptimization = false,
    this.notifications = false,
    this.isChecking = false,
  });

  bool get allGranted =>
      usageStats &&
      accessibility &&
      overlay &&
      deviceAdmin &&
      batteryOptimization &&
      notifications;
  int get grantedCount => [
        usageStats,
        accessibility,
        overlay,
        deviceAdmin,
        batteryOptimization,
        notifications
      ].where((e) => e).length;

  PermissionState copyWith({
    bool? usageStats,
    bool? accessibility,
    bool? overlay,
    bool? deviceAdmin,
    bool? batteryOptimization,
    bool? notifications,
    bool? isChecking,
  }) =>
      PermissionState(
        usageStats: usageStats ?? this.usageStats,
        accessibility: accessibility ?? this.accessibility,
        overlay: overlay ?? this.overlay,
        deviceAdmin: deviceAdmin ?? this.deviceAdmin,
        batteryOptimization: batteryOptimization ?? this.batteryOptimization,
        notifications: notifications ?? this.notifications,
        isChecking: isChecking ?? this.isChecking,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class PermissionNotifier extends StateNotifier<PermissionState> {
  PermissionNotifier() : super(const PermissionState()) {
    checkAll();
  }

  final _native = NativeChannelService();

  Future<void> checkAll() async {
    // Only show checking state if we don't have current results
    if (!state.isChecking) state = state.copyWith(isChecking: true);

    final results = await Future.wait([
      _native.hasUsageStatsPermission(),
      _native.hasAccessibilityPermission(),
      _native.hasOverlayPermission(),
      _native.isDeviceAdminActive(),
      _native.isIgnoringBatteryOptimizations(),
      _native.hasNotificationPermission(),
    ]);

    state = PermissionState(
      usageStats: results[0],
      accessibility: results[1],
      overlay: results[2],
      deviceAdmin: results[3],
      batteryOptimization: results[4],
      notifications: results[5],
      isChecking: false,
    );
  }

  Future<void> requestUsageStats() async {
    await _native.openUsageStatsSettings();
    await checkAll();
  }

  Future<void> requestAccessibility() async {
    await _native.openAccessibilitySettings();
    await checkAll();
  }

  Future<void> requestOverlay() async {
    await _native.openOverlaySettings();
    await checkAll();
  }

  Future<void> requestDeviceAdmin() async {
    await _native.requestDeviceAdmin();
    await checkAll();
  }

  Future<void> requestBatteryOptimization() async {
    await _native.openBatteryOptimizationSettings();
    await checkAll();
  }

  Future<void> requestNotifications() async {
    await _native.requestNotificationPermission();
    await checkAll();
  }
}

final permissionProvider =
    StateNotifierProvider<PermissionNotifier, PermissionState>(
  (ref) => PermissionNotifier(),
);
