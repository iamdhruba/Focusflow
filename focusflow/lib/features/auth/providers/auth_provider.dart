import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/core/services/auth_service.dart';
import 'package:focusflow/core/storage/secure_storage.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? user,
    bool? isLoading,
    String? error,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );

  bool get strictMode => (user?['strictMode'] as bool?) ?? false;
  int get dailyGoalMinutes => (user?['dailyGoalMinutes'] as num?)?.toInt() ?? 120;
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  final _auth = AuthService();

  Future<void> _init() async {
    final authenticated = await SecureStorage.isAuthenticated();
    if (authenticated) {
      final result = await _auth.getMe();
      if (result.success) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: result.user,
        );
      } else {
        await SecureStorage.clearAll();
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _auth.register(name: name, email: email, password: password);
    if (result.success) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isLoading: false,
      );
      return true;
    }
    state = state.copyWith(isLoading: false, error: result.message);
    return false;
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _auth.login(email: email, password: password);
    if (result.success) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isLoading: false,
      );
      return true;
    }
    state = state.copyWith(isLoading: false, error: result.message);
    return false;
  }

  Future<bool> updateStrictMode({
    bool? enabled,
    String? pin,
    int? dailyGoalMinutes,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _auth.updateStrictMode(
      enabled: enabled ?? strictMode,
      pin: pin,
      dailyGoalMinutes: dailyGoalMinutes,
    );
    if (result.success) {
      final updatedUser = Map<String, dynamic>.from(state.user ?? {});
      if (enabled != null) updatedUser['strictMode'] = enabled;
      if (dailyGoalMinutes != null) {
        updatedUser['dailyGoalMinutes'] = dailyGoalMinutes;
      }
      state = state.copyWith(isLoading: false, user: updatedUser);
      return true;
    }
    state = state.copyWith(isLoading: false, error: result.message);
    return false;
  }

  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
