import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/core/services/policy_service.dart';
import 'package:focusflow/core/services/native_channel_service.dart';
import 'package:focusflow/core/storage/secure_storage.dart';

// ── App Policy Model ──────────────────────────────────────────────────────────

class AppPolicyModel {
  final String? id;
  final String packageName;
  final String appName;
  final int timeLimitMinutes;
  final String resetCycle;
  final bool isActive;
  final int todayUsageMs;
  final bool isOverLimit;

  const AppPolicyModel({
    this.id,
    required this.packageName,
    required this.appName,
    this.timeLimitMinutes = 60,
    this.resetCycle = 'daily',
    this.isActive = true,
    this.todayUsageMs = 0,
    this.isOverLimit = false,
  });

  double get progressFraction {
    if (timeLimitMinutes == 0) return 1.0;
    return (todayUsageMs / (timeLimitMinutes * 60 * 1000)).clamp(0.0, 1.0);
  }

  String get usedFormatted {
    final mins = todayUsageMs ~/ 60000;
    if (mins < 60) return '${mins}m';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  String get limitFormatted {
    if (timeLimitMinutes == 0) return 'Blocked';
    if (timeLimitMinutes < 60) return '${timeLimitMinutes}m';
    return '${timeLimitMinutes ~/ 60}h ${timeLimitMinutes % 60}m';
  }

  factory AppPolicyModel.fromJson(Map<String, dynamic> json) => AppPolicyModel(
        id: json['id']?.toString() ?? json['_id']?.toString(),
        packageName: json['packageName'] ?? '',
        appName: json['appName'] ?? '',
        timeLimitMinutes: (json['timeLimitMinutes'] as num?)?.toInt() ?? 60,
        resetCycle: json['resetCycle'] ?? 'daily',
        isActive: json['isActive'] as bool? ?? true,
        todayUsageMs: (json['todayUsageMs'] as num?)?.toInt() ?? 0,
        isOverLimit: json['isOverLimit'] as bool? ?? false,
      );

  AppPolicyModel copyWith({
    String? id,
    String? packageName,
    String? appName,
    int? timeLimitMinutes,
    String? resetCycle,
    bool? isActive,
    int? todayUsageMs,
    bool? isOverLimit,
  }) =>
      AppPolicyModel(
        id: id ?? this.id,
        packageName: packageName ?? this.packageName,
        appName: appName ?? this.appName,
        timeLimitMinutes: timeLimitMinutes ?? this.timeLimitMinutes,
        resetCycle: resetCycle ?? this.resetCycle,
        isActive: isActive ?? this.isActive,
        todayUsageMs: todayUsageMs ?? this.todayUsageMs,
        isOverLimit: isOverLimit ?? this.isOverLimit,
      );
}

// ── Installed App Model ───────────────────────────────────────────────────────

class InstalledApp {
  final String packageName;
  final String appName;
  final String? iconBase64;

  const InstalledApp({
    required this.packageName,
    required this.appName,
    this.iconBase64,
  });

  factory InstalledApp.fromMap(Map<String, dynamic> map) => InstalledApp(
        packageName: map['packageName'] ?? '',
        appName: map['appName'] ?? '',
        iconBase64: map['icon']?.toString(),
      );
}

// ── Apps State ────────────────────────────────────────────────────────────────

class AppsState {
  final List<AppPolicyModel> policies;
  final List<InstalledApp> installedApps;
  final bool isLoading;
  final bool isSyncing;
  final bool masterBlock;
  final String? error;
  final DateTime? lastSync;

  const AppsState({
    this.policies = const [],
    this.installedApps = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.masterBlock = false,
    this.error,
    this.lastSync,
  });

  AppsState copyWith({
    List<AppPolicyModel>? policies,
    List<InstalledApp>? installedApps,
    bool? isLoading,
    bool? isSyncing,
    bool? masterBlock,
    String? error,
    DateTime? lastSync,
  }) =>
      AppsState(
        policies: policies ?? this.policies,
        installedApps: installedApps ?? this.installedApps,
        isLoading: isLoading ?? this.isLoading,
        isSyncing: isSyncing ?? this.isSyncing,
        masterBlock: masterBlock ?? this.masterBlock,
        error: error,
        lastSync: lastSync ?? this.lastSync,
      );

  int get totalUsageMs => policies.fold(0, (sum, p) => sum + p.todayUsageMs);
  int get overLimitCount => policies.where((p) => p.isOverLimit).length;
}

// ── Apps Notifier ─────────────────────────────────────────────────────────────

class AppsNotifier extends StateNotifier<AppsState> {
  AppsNotifier() : super(const AppsState()) {
    load();
  }

  final _policyService = PolicyService();
  final _native = NativeChannelService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _policyService.getPolicies();
    if (result.success) {
      final policies = result.policies!
          .map(AppPolicyModel.fromJson)
          .toList();
      state = state.copyWith(policies: policies, isLoading: false);
    } else {
      state = state.copyWith(isLoading: false, error: result.message);
    }
  }

  Future<void> loadInstalledApps() async {
    final apps = await _native.getInstalledApps();
    state = state.copyWith(
      installedApps: apps.map(InstalledApp.fromMap).toList(),
    );
  }

  Future<bool> upsertPolicy({
    required String packageName,
    required String appName,
    required int timeLimitMinutes,
    bool isActive = true,
  }) async {
    final result = await _policyService.upsertPolicy(
      packageName: packageName,
      appName: appName,
      timeLimitMinutes: timeLimitMinutes,
      isActive: isActive,
    );
    if (result.success) {
      await load();
      await _pushRulesToNative();
      return true;
    }
    state = state.copyWith(error: result.message);
    return false;
  }

  Future<void> togglePolicy(String id) async {
    final result = await _policyService.togglePolicy(id);
    if (result.success) {
      await load();
      await _pushRulesToNative();
    }
  }

  Future<void> deletePolicy(String id) async {
    final result = await _policyService.deletePolicy(id);
    if (result.success) {
      state = state.copyWith(
        policies: state.policies.where((p) => p.id != id).toList(),
      );
      await _pushRulesToNative();
    }
  }

  /// Pushes current state to the native Android blocking engine.
  Future<void> _pushRulesToNative() async {
    if (state.policies.isEmpty) return;
    await _native.updateBlockingRules(
      state.policies.map((p) => {
        'packageName': p.packageName,
        'timeLimitMinutes': p.timeLimitMinutes,
        'isActive': p.isActive,
        'todayUsageMs': p.todayUsageMs,
      }).toList(),
    );
  }

  /// Sync usage data from device to server, then update local rules.
  Future<void> syncUsage() async {
    state = state.copyWith(isSyncing: true);
    try {
      final usageMap = await _native.getTodayUsageStats();
      final deviceId = await SecureStorage.getUserId() ?? 'unknown';
      final usageReport = usageMap.entries
          .map((e) => {'packageName': e.key, 'usedMs': e.value})
          .toList();

      final result = await _policyService.sync(
        deviceId: deviceId,
        usageReport: usageReport,
      );

      if (result.success) {
        final policies = result.policies!.map(AppPolicyModel.fromJson).toList();
        state = state.copyWith(
          policies: policies,
          masterBlock: result.masterBlock,
          isSyncing: false,
          lastSync: DateTime.now(),
        );
        // Push updated rules to native blocking engine
        await _pushRulesToNative();
      } else {
        state = state.copyWith(isSyncing: false, error: result.message);
      }
    } catch (e) {
      state = state.copyWith(isSyncing: false, error: e.toString());
    }
  }
}

final appsProvider = StateNotifierProvider<AppsNotifier, AppsState>(
  (ref) => AppsNotifier(),
);
