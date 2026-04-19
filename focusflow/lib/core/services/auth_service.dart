import '../constants/api_constants.dart';
import '../services/api_service.dart';
import '../storage/secure_storage.dart';

/// Typed result wrapper to avoid throwing exceptions in the UI layer.
class AuthResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? user;

  const AuthResult({required this.success, this.message, this.user});
}

/// Handles all authentication API calls and local session management.
class AuthService {
  final ApiService _api = ApiService();

  /// Register a new account.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _api.post(ApiConstants.register, data: {
        'name': name,
        'email': email,
        'password': password,
      });
      await _persistSession(res.data);
      return AuthResult(success: true, user: res.data['user']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Login with email + password.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _api.post(ApiConstants.login, data: {
        'email': email,
        'password': password,
      });
      await _persistSession(res.data);
      return AuthResult(success: true, user: res.data['user']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Fetch current user profile.
  Future<AuthResult> getMe() async {
    try {
      final res = await _api.get(ApiConstants.me);
      return AuthResult(success: true, user: res.data['user']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Toggle strict mode on/off and update goals.
  Future<AuthResult> updateStrictMode({
    required bool enabled,
    String? pin,
    int? dailyGoalMinutes,
  }) async {
    try {
      final res = await _api.patch(ApiConstants.strictMode, data: {
        'strictMode': enabled,
        if (pin != null) 'pin': pin,
        if (dailyGoalMinutes != null) 'dailyGoalMinutes': dailyGoalMinutes,
      });
      return AuthResult(success: true, message: res.data['message']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Clear local session (logout).
  Future<void> logout() => SecureStorage.clearAll();

  /// Persist tokens + user metadata locally after login/register.
  Future<void> _persistSession(Map<String, dynamic> data) async {
    final token = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final user = data['user'] as Map<String, dynamic>?;

    if (token != null) await SecureStorage.saveAccessToken(token);
    if (refreshToken != null) await SecureStorage.saveRefreshToken(refreshToken);
    if (user != null) {
      if (user['id'] != null) await SecureStorage.saveUserId(user['id'].toString());
      if (user['email'] != null) await SecureStorage.saveUserEmail(user['email'].toString());
    }
  }

  /// Request password reset token.
  Future<AuthResult> forgotPassword(String email) async {
    try {
      final res = await _api.post('/auth/forgot-password', data: {'email': email});
      return AuthResult(success: true, message: res.data['message']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Reset password with token.
  Future<AuthResult> resetPassword({required String token, required String newPassword}) async {
    try {
      final res = await _api.put('/auth/reset-password/$token', data: {'password': newPassword});
      return AuthResult(success: true, user: res.data['user']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Request PIN reset code (authenticated).
  Future<AuthResult> forgotPIN() async {
    try {
      final res = await _api.post('/auth/forgot-pin');
      return AuthResult(success: true, message: res.data['message']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }

  /// Reset PIN with code (authenticated).
  Future<AuthResult> resetPIN({required String code, required String newPin}) async {
    try {
      final res = await _api.put('/auth/reset-pin', data: {'code': code, 'newPin': newPin});
      return AuthResult(success: true, message: res.data['message']);
    } catch (e) {
      return AuthResult(success: false, message: ApiService.parseError(e));
    }
  }
}
