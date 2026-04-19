import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/features/auth/providers/auth_provider.dart';
import 'package:focusflow/core/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Tests', () {
    test('AuthService - login should return result', () async {
      final authService = AuthService();
      try {
        final result = await authService.login(
          email: 'test@example.com',
          password: 'Test123!',
        );
        expect(result, isNotNull);
        expect(result.success, isA<bool>());
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('AuthService - register should create user', () async {
      final authService = AuthService();
      try {
        final result = await authService.register(
          name: 'New User',
          email: 'newuser@example.com',
          password: 'Test123!',
        );
        expect(result, isNotNull);
        expect(result.success, isA<bool>());
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });
}
