import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central access point for all API-related constants.
/// Values are loaded from .env at startup.
class ApiConstants {
  ApiConstants._();

  static String get baseUrl {
    final env = dotenv.env['APP_ENV'] ?? 'development';
    final url = dotenv.env['API_BASE_URL'];
    // Fail fast in production so a missing .env can't silently fall back
    // to a hardcoded URL that may be stale or incorrect.
    if (env == 'production') {
      if (url == null || url.trim().isEmpty) {
        throw StateError(
          'API_BASE_URL must be set in .env when APP_ENV=production',
        );
      }
      return url;
    }
    return url?.trim().isNotEmpty == true
        ? url!
        : 'https://focusflow-709d.onrender.com/api/v1';
  }

  static int get syncIntervalMinutes =>
      int.tryParse(dotenv.env['SYNC_INTERVAL_MINUTES'] ?? '15') ?? 15;

  static String get appEnv => dotenv.env['APP_ENV'] ?? 'development';

  // ── Endpoints ──────────────────────────────────────────────────────────────
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';
  static const String strictMode = '/auth/strict-mode';
  static const String forgotPassword = '/auth/forgot-password';
  static String resetPassword(String token) => '/auth/reset-password/$token';
  static const String forgotPIN = '/auth/forgot-pin';
  static const String resetPIN = '/auth/reset-pin';

  static const String policies = '/policies';
  static String togglePolicy(String id) => '/policies/$id/toggle';
  static String deletePolicy(String id) => '/policies/$id';

  // ── Per-screen policies (Phase 4) ──
  static const String screenPolicies = '/screen-policies';
  static String toggleScreenPolicy(String id) => '/screen-policies/$id/toggle';
  static String deleteScreenPolicy(String id) => '/screen-policies/$id';
  static const String syncScreenPolicies = '/screen-policies/sync';

  static const String sync = '/sync';
  static const String syncStatus = '/sync/status';

  // ── Platform Channel Names ─────────────────────────────────────────────────
  static const String usageStatsChannel = 'com.focusflow.app/usageStats';
  static const String permissionChannel = 'com.focusflow.app/permissions';
  static const String blockingChannel = 'com.focusflow.app/blocking';

  // ── WorkManager Task Names ─────────────────────────────────────────────────
  static const String syncTaskName = 'focusflow_sync_task';
  static const String syncTaskTag = 'focusflow_sync';

  // ── Timeouts ──────────────────────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
