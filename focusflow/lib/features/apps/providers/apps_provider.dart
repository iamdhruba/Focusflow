import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/core/services/local_policy_service.dart';
import 'package:focusflow/core/services/native_channel_service.dart';
import 'package:focusflow/core/services/screen_policy_service.dart';
import 'package:focusflow/core/services/screen_policy_sync.dart';
import 'package:focusflow/core/storage/local_database.dart';

// ── App Policy Model ──────────────────────────────────────────────────────────

class AppPolicyModel {
  final int? id;
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

  factory AppPolicyModel.fromMap(Map<String, dynamic> map) => AppPolicyModel(
        id: map['id'] as int?,
        packageName: map['packageName'] ?? '',
        appName: map['appName'] ?? '',
        timeLimitMinutes: map['timeLimitMinutes'] as int? ?? 60,
        resetCycle: map['resetCycle'] ?? 'daily',
        isActive: (map['isActive'] as int? ?? 1) == 1,
        todayUsageMs: map['todayUsageMs'] as int? ?? 0,
        isOverLimit: (map['isOverLimit'] as int? ?? 0) == 1,
      );

  AppPolicyModel copyWith({
    int? id,
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

// ── Screen Policy Model ─────────────────────────────────────────────────────

/// One per-screen blocking rule (e.g. "block Instagram Reels").
class ScreenPolicyModel {
  final String? serverId; // Mongo _id from `/screen-policies` (nullable until first save)
  final String packageName;
  final String screenKey;
  final String friendlyName;
  final int timeLimitMinutes; // 0 = full block, >0 = soft cap
  final bool isActive;
  final int todayUsageMs;

  const ScreenPolicyModel({
    this.serverId,
    required this.packageName,
    required this.screenKey,
    required this.friendlyName,
    this.timeLimitMinutes = 0,
    this.isActive = false,
    this.todayUsageMs = 0,
  });

  bool get isFullBlock => isActive && timeLimitMinutes == 0;

  factory ScreenPolicyModel.fromMap(Map<String, dynamic> map) =>
      ScreenPolicyModel(
        serverId: map['_id']?.toString() ?? map['serverId']?.toString(),
        packageName: map['packageName'] ?? '',
        screenKey: map['screenKey'] ?? '',
        friendlyName: map['friendlyName'] ?? '',
        timeLimitMinutes: map['timeLimitMinutes'] as int? ?? 0,
        isActive: map['isActive'] is bool
            ? map['isActive'] as bool
            : (map['isActive'] as int? ?? 0) == 1,
        todayUsageMs: map['todayUsageMs'] as int? ?? 0,
      );

  /// Snake-case shape used by the LocalDatabase `screen_policies` table.
  /// Accepts an optional [syncStatus] override so that mirror-back
  /// operations (e.g. cold-launch hydrating from the server) can stamp
  /// rows as 'synced' instead of leaving the default 'pending' that
  /// `LocalDatabase.upsertScreenPolicy` would otherwise stamp on every
  /// row, causing recovered server state to be re-pushed.
  Map<String, dynamic> toSqliteRow({String? syncStatus}) => {
        'packageName': packageName,
        'screenKey': screenKey,
        'friendlyName': friendlyName,
        'timeLimitMinutes': timeLimitMinutes,
        'isActive': isActive ? 1 : 0,
        'todayUsageMs': todayUsageMs,
        if (serverId != null) 'serverId': serverId,
        if (syncStatus != null) 'syncStatus': syncStatus,
      };

  /// camelCase shape used by the Native MethodChannel + the backend REST API.
  Map<String, dynamic> toMethodChannelMap() => {
        'packageName': packageName,
        'screenKey': screenKey,
        'timeLimitMinutes': timeLimitMinutes,
        'isActive': isActive,
      };

  ScreenPolicyModel copyWith({
    String? serverId,
    String? packageName,
    String? screenKey,
    String? friendlyName,
    int? timeLimitMinutes,
    bool? isActive,
    int? todayUsageMs,
  }) =>
      ScreenPolicyModel(
        serverId: serverId ?? this.serverId,
        packageName: packageName ?? this.packageName,
        screenKey: screenKey ?? this.screenKey,
        friendlyName: friendlyName ?? this.friendlyName,
        timeLimitMinutes: timeLimitMinutes ?? this.timeLimitMinutes,
        isActive: isActive ?? this.isActive,
        todayUsageMs: todayUsageMs ?? this.todayUsageMs,
      );

  /// Phase 4: content-equality is required for Riverpod `select()` to
  /// avoid pointless widget rebuilds. Without this override, every channel
  /// flush → state.copyWith(screenPolicies: updated) would rebuild the
  /// AppDetailScreen row even when only an unrelated screen's totals moved.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScreenPolicyModel &&
          serverId == other.serverId &&
          packageName == other.packageName &&
          screenKey == other.screenKey &&
          friendlyName == other.friendlyName &&
          timeLimitMinutes == other.timeLimitMinutes &&
          isActive == other.isActive &&
          todayUsageMs == other.todayUsageMs);

  @override
  int get hashCode => Object.hash(
        serverId,
        packageName,
        screenKey,
        friendlyName,
        timeLimitMinutes,
        isActive,
        todayUsageMs,
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
  final List<ScreenPolicyModel> screenPolicies;
  final List<InstalledApp> installedApps;
  final bool isLoading;
  final bool masterBlock;
  final int dailyGoalMinutes;
  final int blockedAttempts;
  final int phonePickups;
  final String? error;

  const AppsState({
    this.policies = const [],
    this.screenPolicies = const [],
    this.installedApps = const [],
    this.isLoading = false,
    this.masterBlock = false,
    this.dailyGoalMinutes = 120,
    this.blockedAttempts = 0,
    this.phonePickups = 0,
    this.error,
  });

  AppsState copyWith({
    List<AppPolicyModel>? policies,
    List<ScreenPolicyModel>? screenPolicies,
    List<InstalledApp>? installedApps,
    bool? isLoading,
    bool? masterBlock,
    int? dailyGoalMinutes,
    int? blockedAttempts,
    int? phonePickups,
    String? error,
  }) =>
      AppsState(
        policies: policies ?? this.policies,
        screenPolicies: screenPolicies ?? this.screenPolicies,
        installedApps: installedApps ?? this.installedApps,
        isLoading: isLoading ?? this.isLoading,
        masterBlock: masterBlock ?? this.masterBlock,
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        blockedAttempts: blockedAttempts ?? this.blockedAttempts,
        phonePickups: phonePickups ?? this.phonePickups,
        error: error,
      );

  int get totalUsageMs => policies.fold(0, (sum, p) => sum + p.todayUsageMs);
  int get overLimitCount => policies.where((p) => p.isOverLimit).length;
  double get dailyProgress => (totalUsageMs / (dailyGoalMinutes * 60 * 1000)).clamp(0.0, 1.0);

  /// Helper — return all screen policies that target [packageName].
  List<ScreenPolicyModel> screensFor(String packageName) =>
      screenPolicies.where((s) => s.packageName == packageName).toList();
}

// ── Apps Notifier ─────────────────────────────────────────────────────────────

class AppsNotifier extends StateNotifier<AppsState> {
  AppsNotifier() : super(const AppsState()) {
    load();
  }

  final _localService = LocalPolicyService();
  final _native = NativeChannelService();
  final _screenService = ScreenPolicyService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final policiesData = await _localService.getPolicies();
      final policies = policiesData.map(AppPolicyModel.fromMap).toList();

      final goalStr = await _localService.getSetting('dailyGoalMinutes');
      final dailyGoal = goalStr != null ? int.parse(goalStr) : state.dailyGoalMinutes;

      final blocked = await _native.getBlockedAttempts();
      final pickups = await _native.getPhonePickups();

      // Phase 2: read the local SQLite cache first (always available, even
      // offline). Then ask the backend for the source-of-truth merge.
      // Backend wins on conflict because the user might have changed rules
      // from another device.
      final localScreenRows = await LocalDatabase.instance.getScreenPolicies();
      final localScreenPolicies = localScreenRows
          .map(ScreenPolicyModel.fromMap)
          .toList();

      List<ScreenPolicyModel> remoteScreenPolicies;
      try {
        final screenRes = await _screenService.getScreenPolicies();
        remoteScreenPolicies = (screenRes.policies ?? const [])
            .map(ScreenPolicyModel.fromMap)
            .toList();

        // Cache the freshest remote rules into SQLite so the next cold-launch
        // can boot instantly without waiting on the network. The
        // syncStatus='synced' override prevents the bulk-sync job from
        // re-pushing the recovered server state — only locally-pending
        // rows should get pushed.
        for (final p in remoteScreenPolicies) {
          await LocalDatabase.instance
              .upsertScreenPolicy(p.toSqliteRow(syncStatus: 'synced'));
        }
      } catch (_) {
        // Backend unreachable — fall back to whatever SQLite already had.
        remoteScreenPolicies = const [];
      }

      // Merge: keep all server-confirmed rules, fold in any local-only rules
      // that the server doesn't know about yet.
      final merged = <String, ScreenPolicyModel>{
        for (final p in remoteScreenPolicies)
          _key(p): p,
        for (final p in localScreenPolicies)
          if (!_containsKey(remoteScreenPolicies, p)) _key(p): p,
      };

      // Phase 4: cross-check the in-memory policy list against the
      // authoritative daily totals persisted natively in SharedPreferences.
      // Native wins on conflict because the AccessibilityService could
      // have accumulated dwell while the Dart side was killed.
      try {
        final nativeTotals = await _native.getScreenUsageTotals();
        if (nativeTotals.isNotEmpty) {
          final byKey = <String, int>{
            for (final entry in nativeTotals)
              '${entry['packageName']}:${entry['screenKey']}':
                  (entry['usedMs'] as num? ?? 0).toInt(),
          };
          final aligned = merged.values.map((p) {
            final k = _key(p);
            final nativeMs = byKey[k];
            return nativeMs != null ? p.copyWith(todayUsageMs: nativeMs) : p;
          }).toList();
          merged
            ..clear()
            ..addEntries(aligned.map((p) => MapEntry(_key(p), p)));
        }
      } catch (_) {
        // No native totals available (web / plugin missing) — proceed with
        // whatever subscription state we already have.
      }

      state = state.copyWith(
        policies: policies,
        screenPolicies: merged.values.toList(),
        dailyGoalMinutes: dailyGoal,
        blockedAttempts: blocked,
        phonePickups: pickups,
        isLoading: false,
      );
      await _pushRulesToNative();
      await _pushScreenRulesToNative();
      // Phase 3: cold-launch sync — push any locally-pending screen-policy
      // deltas (and pending tombstones) so a fresh install post-wipe can
      // recover via /api/v1/screen-policies later. Best-effort: if the
      // network is down, rows stay marked 'pending' for the next foreground
      // sync.
      await syncScreenPoliciesToServer();
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  static String _key(ScreenPolicyModel p) => '${p.packageName}:${p.screenKey}';
  static bool _containsKey(List<ScreenPolicyModel> list, ScreenPolicyModel p) =>
      list.any((e) => _key(e) == _key(p));

  Future<void> updateDailyGoal(int minutes) async {
    state = state.copyWith(dailyGoalMinutes: minutes);
    try {
      await _localService.saveSetting('dailyGoalMinutes', minutes.toString());
    } catch (_) {
      // sqflite not available on web — already updated in memory.
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
    try {
      await _localService.upsertPolicy(
        packageName: packageName,
        appName: appName,
        timeLimitMinutes: timeLimitMinutes,
        isActive: isActive,
      );
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> togglePolicy(String packageName, bool isActive) async {
    await _localService.togglePolicy(packageName, isActive);
    await load();
  }

  Future<void> deletePolicy(String packageName) async {
    await _localService.deletePolicy(packageName);
    await load();
  }

  // ── Phase 2: per-screen rule methods (backend + LocalDatabase mirror) ────

  /// Persist [policy] to BOTH the backend (source of truth) and the local
  /// SQLite cache, then sync to native. If the backend write fails we keep
  /// the local row so the next cold launch doesn't lose the user's choice.
  Future<bool> upsertScreenPolicy(ScreenPolicyModel policy) async {
    // Write to SQLite first so the rule survives a crash before the
    // network round-trip finishes. The mark-pending happens implicitly:
    // upsertScreenPolicy sets syncStatus='pending' (default) so the delta-
    // sync job will pick it up on the next push window.
    try {
      await LocalDatabase.instance.upsertScreenPolicy(policy.toSqliteRow());
    } catch (_) {
      // sqflite not available on web — fine, we still have backend copy.
    }

    try {
      final res = await _screenService.upsertScreenPolicy(
        packageName: policy.packageName,
        screenKey: policy.screenKey,
        friendlyName: policy.friendlyName,
        timeLimitMinutes: policy.timeLimitMinutes,
        isActive: policy.isActive,
      );
      if (!res.success) {
        // Even when the live POST fails we still queue the row through the
        // delta-sync job, so a flaky connection doesn't drop the user's
        // choice. The next foreground / WorkManager run will retry.
        await syncScreenPoliciesToServer();
        state = state.copyWith(error: res.message);
        return false;
      }

      // Replace the local copy with the saved one (carries server _id) and
      // mark it synced — we've just talked to the server successfully.
      final saved = res.policy != null
          ? ScreenPolicyModel.fromMap(res.policy!)
          : policy;
      try {
        await LocalDatabase.instance.upsertScreenPolicy({
          ...saved.toSqliteRow(),
          'syncStatus': 'synced',
          'syncAttempts': 0,
        });
      } catch (_) {}

      final updated = [
        ...state.screenPolicies.where((p) =>
            !(p.packageName == saved.packageName &&
                p.screenKey == saved.screenKey)),
        saved,
      ];
      state = state.copyWith(screenPolicies: updated);
      await _pushScreenRulesToNative();
      return true;
    } catch (e) {
      // Fall back to delta-sync so the row reaches the server eventually.
      await syncScreenPoliciesToServer();
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> deleteScreenPolicy(ScreenPolicyModel policy) async {
    try {
      await LocalDatabase.instance
          .deleteScreenPolicy(policy.packageName, policy.screenKey);
    } catch (_) {}

    if (policy.serverId != null) {
      try {
        await _screenService.deleteScreenPolicy(policy.serverId!);
      } catch (_) {
        // best-effort server delete; queue the deletion for delta-sync
        // instead so a flaky connection doesn't drop the intent.
      }
    }
    final remaining = state.screenPolicies
        .where((p) => !(p.packageName == policy.packageName &&
            p.screenKey == policy.screenKey))
        .toList();
    state = state.copyWith(screenPolicies: remaining);
    await _pushScreenRulesToNative();
    // Tell the server about this deletion on the next sync window. We use
    // a row already deleted locally, so we record the tombstone in a tiny
    // settings table addendum rather than resurrecting the row.
    try {
      await _recordPendingTombstone(policy.packageName, policy.screenKey);
      await syncScreenPoliciesToServer();
    } catch (_) {}
  }

  // ── Phase 3: per-user delta-sync ──────────────────────────────────────────

  /// Push any locally-pending screen-policy changes (including pending
  /// tombstones from `deleteScreenPolicy`) to
  /// `POST /api/v1/screen-policies/sync`. Marks each row's `syncStatus`
  /// per the per-row outcome and persists a `screenPoliciesLastSyncAt` ISO
  /// marker so we can audit when we last talked to the server.
  ///
  /// Safe to call repeatedly; idempotent bookkeeping via per-row status.
  /// Failed calls leave rows in 'failed' and bump `syncAttempts` so future
  /// calls can either retry (depending on policy) or surface to the user.
  Future<SyncScreenPolicyResult?> syncScreenPoliciesToServer() {
    // Delegate to the shared orchestrator so the WorkManager body in
    // main.dart and this foreground path can't drift apart. The
    // orchestrator owns the per-row outcome handling, tombstone clearing,
    // and `screenPoliciesLastSyncAt` stamping end-to-end.
    return performScreenPolicySync(
      db: LocalDatabase.instance,
      local: _localService,
      postSync: (payload) => _screenService.syncScreenPolicies(payload),
    );
  }

  // Tombstone bookkeeping split out so the delete path doesn't conflate
  // with the bulk-sync orchestrator above.
  Future<void> _recordPendingTombstone(
    String packageName,
    String screenKey,
  ) {
    return _localService.recordPendingTombstone(packageName, screenKey);
  }

  /// Legacy overload — preserved for any caller still passing a server id.
  Future<void> deleteScreenPolicyByServerId(String serverId) =>
      deleteScreenPolicy(state.screenPolicies.firstWhere(
        (p) => p.serverId == serverId,
        orElse: () => throw StateError('No policy with serverId=$serverId'),
      ));

  // ── Phase 2: per-screen usage attribution ────────────────────────────────

  /// Update `todayUsageMs` for one matching screen policy. Called from
  /// FocusAccessibilityService via the future native bridge.
  Future<void> updateScreenUsage(
    String packageName,
    String screenKey,
    int usedMs,
  ) async {
    try {
      await LocalDatabase.instance
          .updateScreenUsage(packageName, screenKey, usedMs);

      // Refresh in-memory copy.
      final updated = state.screenPolicies.map((p) {
        if (p.packageName == packageName && p.screenKey == screenKey) {
          return p.copyWith(todayUsageMs: usedMs);
        }
        return p;
      }).toList();
      state = state.copyWith(screenPolicies: updated);
    } catch (_) {
      // sqflite can be unavailable on some platforms; ignore.
    }
  }

  // ── Native push ──────────────────────────────────────────────────────────

  Future<void> _pushRulesToNative() async {
    await _native.updateBlockingRules(
      state.policies.map((p) => {
        'packageName': p.packageName,
        'timeLimitMinutes': p.timeLimitMinutes,
        'isActive': p.isActive,
        'todayUsageMs': p.todayUsageMs,
      }).toList(),
    );
  }

  Future<void> _pushScreenRulesToNative() async {
    await _native.updateScreenBlockingRules(
      state.screenPolicies
          .where((p) => p.isActive)
          .map((p) => p.toMethodChannelMap())
          .toList(),
    );
  }

  Future<void> refreshUsage() async {
    final usageMap = await _native.getTodayUsageStats();
    for (final entry in usageMap.entries) {
      await _localService.updateUsage(entry.key, entry.value);
    }
    await load();
  }
}

final appsProvider = StateNotifierProvider<AppsNotifier, AppsState>(
  (ref) => AppsNotifier(),
);
