import '../constants/api_constants.dart';
import '../services/api_service.dart';

class PolicyResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>>? policies;
  final Map<String, dynamic>? policy;

  const PolicyResult({
    required this.success,
    this.message,
    this.policies,
    this.policy,
  });
}

/// Handles all AppPolicy API calls.
class PolicyService {
  final ApiService _api = ApiService();

  /// Fetch all policies for the authenticated user.
  Future<PolicyResult> getPolicies() async {
    try {
      final res = await _api.get(ApiConstants.policies);
      final list = (res.data['policies'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return PolicyResult(success: true, policies: list);
    } catch (e) {
      return PolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Create or update a policy (upsert).
  Future<PolicyResult> upsertPolicy({
    required String packageName,
    required String appName,
    required int timeLimitMinutes,
    String resetCycle = 'daily',
    bool isActive = true,
  }) async {
    try {
      final res = await _api.post(ApiConstants.policies, data: {
        'packageName': packageName,
        'appName': appName,
        'timeLimitMinutes': timeLimitMinutes,
        'resetCycle': resetCycle,
        'isActive': isActive,
      });
      return PolicyResult(success: true, policy: res.data['policy']);
    } catch (e) {
      return PolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Toggle a policy on/off.
  Future<PolicyResult> togglePolicy(String id) async {
    try {
      final res = await _api.patch(ApiConstants.togglePolicy(id));
      return PolicyResult(success: true, policy: res.data['policy']);
    } catch (e) {
      return PolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Delete a policy permanently.
  Future<PolicyResult> deletePolicy(String id) async {
    try {
      await _api.delete(ApiConstants.deletePolicy(id));
      return const PolicyResult(success: true);
    } catch (e) {
      return PolicyResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Sync usage data and retrieve updated policies.
  Future<SyncResult> sync({
    required String deviceId,
    required List<Map<String, dynamic>> usageReport,
  }) async {
    try {
      final res = await _api.post(ApiConstants.sync, data: {
        'deviceId': deviceId,
        'usageReport': usageReport,
      });
      final list = (res.data['policies'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return SyncResult(
        success: true,
        policies: list,
        strictMode: res.data['strictMode'] as bool? ?? false,
        masterBlock: res.data['masterBlock'] as bool? ?? false,
        timestamp: res.data['timestamp'] as String?,
      );
    } catch (e) {
      return SyncResult(success: false, message: ApiService.parseError(e));
    }
  }
}

class SyncResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>>? policies;
  final bool strictMode;
  final bool masterBlock;
  final String? timestamp;

  const SyncResult({
    required this.success,
    this.message,
    this.policies,
    this.strictMode = false,
    this.masterBlock = false,
    this.timestamp,
  });
}
