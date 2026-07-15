import '../constants/api_constants.dart';
import '../services/api_service.dart';

/// Per-screen policy CRUD — mirrors [PolicyService] but for in-app screens
/// like Instagram Reels or TikTok FYP.
///
/// Backend route: GET|POST /api/v1/screen-policies, PATCH /:id/toggle,
/// DELETE /:id. Behind the same JWT Bearer as /policies.
class ScreenPolicyService {
  final ApiService _api = ApiService();

  /// Fetch all screen policies for the authenticated user.
  /// Optionally narrow by [packageName] (= one host app).
  Future<ScreenPolicyResult> getScreenPolicies({String? packageName}) async {
    try {
      final res = await _api.get(
        ApiConstants.screenPolicies,
        params: packageName != null ? {'packageName': packageName} : null,
      );
      final list = (res.data['policies'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return ScreenPolicyResult(success: true, policies: list);
    } catch (e) {
      return ScreenPolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Create or update a screen policy.
  Future<ScreenPolicyResult> upsertScreenPolicy({
    required String packageName,
    required String screenKey,
    required String friendlyName,
    required int timeLimitMinutes,
    bool isActive = true,
  }) async {
    try {
      final res = await _api.post(
        ApiConstants.screenPolicies,
        data: {
          'packageName': packageName,
          'screenKey': screenKey,
          'friendlyName': friendlyName,
          'timeLimitMinutes': timeLimitMinutes,
          'isActive': isActive,
        },
      );
      return ScreenPolicyResult(success: true, policy: res.data['policy']);
    } catch (e) {
      return ScreenPolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Toggle a screen policy on/off by server-side id.
  Future<ScreenPolicyResult> toggleScreenPolicy(String id) async {
    try {
      final res = await _api.patch(ApiConstants.toggleScreenPolicy(id));
      return ScreenPolicyResult(success: true, policy: res.data['policy']);
    } catch (e) {
      return ScreenPolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Permanently remove a screen policy by server-side id.
  Future<ScreenPolicyResult> deleteScreenPolicy(String id) async {
    try {
      await _api.delete(ApiConstants.deleteScreenPolicy(id));
      return const ScreenPolicyResult(success: true);
    } catch (e) {
      return ScreenPolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Bulk delta-sync. Posts [deltas] (a list of row-shaped maps) to
  /// `POST /api/v1/screen-policies/sync`. The backend applies last-writer-
  /// wins per (userId, packageName, screenKey), returns per-row outcomes
  /// (`applied` / `skipped_newer` / `deleted`) plus a server-print `serverTime`
  /// so the caller can update its `lastSyncAt` marker.
  ///
  /// This is the offline-first write pipeline: changes made on-device while
  /// the network was down (or accumulated while the app was uninstalled
  /// then reinstalled on the same account) propagate up so any device
  /// freshly fetching via `getScreenPolicies` sees the latest user state.
  Future<SyncScreenPolicyResult> syncScreenPolicies(
    List<Map<String, dynamic>> deltas,
  ) async {
    try {
      final res = await _api.post(
        ApiConstants.syncScreenPolicies,
        data: {'policies': deltas},
      );
      final body = res.data;
      final results = (body['results'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return SyncScreenPolicyResult(
        success: body['success'] == true,
        serverTime: body['serverTime']?.toString(),
        applied: body['applied'] as int? ?? 0,
        deleted: body['deleted'] as int? ?? 0,
        skipped: body['skipped'] as int? ?? 0,
        results: results,
        message: body['message']?.toString(),
      );
    } catch (e) {
      return SyncScreenPolicyResult(
        success: false,
        message: ApiService.parseError(e),
      );
    }
  }
}

class SyncScreenPolicyResult {
  final bool success;
  final String? message;
  final String? serverTime;
  final int applied;
  final int deleted;
  final int skipped;
  final List<Map<String, dynamic>> results;

  const SyncScreenPolicyResult({
    required this.success,
    this.message,
    this.serverTime,
    this.applied = 0,
    this.deleted = 0,
    this.skipped = 0,
    this.results = const [],
  });
}

class ScreenPolicyResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>>? policies;
  final Map<String, dynamic>? policy;

  const ScreenPolicyResult({
    required this.success,
    this.message,
    this.policies,
    this.policy,
  });
}
