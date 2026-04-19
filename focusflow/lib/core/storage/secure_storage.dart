import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper around flutter_secure_storage.
/// Provides typed accessors for all persisted auth tokens and user data.
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    webOptions: WebOptions(dbName: 'FocusFlow'),
  );

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';
  static const _keyUserEmail = 'user_email';
  static const _keyOnboardingDone = 'onboarding_done';

  // ── Access Token ────────────────────────────────────────────────────────────
  static Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccessToken, value: token);

  static Future<String?> getAccessToken() =>
      _storage.read(key: _keyAccessToken);

  // ── Refresh Token ───────────────────────────────────────────────────────────
  static Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _keyRefreshToken);

  // ── User ID ─────────────────────────────────────────────────────────────────
  static Future<void> saveUserId(String id) =>
      _storage.write(key: _keyUserId, value: id);

  static Future<String?> getUserId() => _storage.read(key: _keyUserId);

  // ── User Email ──────────────────────────────────────────────────────────────
  static Future<void> saveUserEmail(String email) =>
      _storage.write(key: _keyUserEmail, value: email);

  static Future<String?> getUserEmail() => _storage.read(key: _keyUserEmail);

  // ── Onboarding ──────────────────────────────────────────────────────────────
  static Future<void> setOnboardingDone() =>
      _storage.write(key: _keyOnboardingDone, value: 'true');

  static Future<bool> isOnboardingDone() async {
    final val = await _storage.read(key: _keyOnboardingDone);
    return val == 'true';
  }

  // ── Clear All ───────────────────────────────────────────────────────────────
  static Future<void> clearAll() => _storage.deleteAll();

  /// Check if the user is currently authenticated
  static Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
