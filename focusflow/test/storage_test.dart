import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Secure Storage Tests', () {
    late FlutterSecureStorage storage;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      storage = const FlutterSecureStorage();
    });

    test('SecureStorage - should save and retrieve access token', () async {
      const testToken = 'test-jwt-token';
      await storage.write(key: 'access_token', value: testToken);
      final token = await storage.read(key: 'access_token');
      expect(token, equals(testToken));
    });

    test('SecureStorage - should save and retrieve userId', () async {
      const testUserId = 'user-123';
      await storage.write(key: 'user_id', value: testUserId);
      final userId = await storage.read(key: 'user_id');
      expect(userId, equals(testUserId));
    });

    test('SecureStorage - should handle onboarding flag', () async {
      await storage.write(key: 'onboarding_done', value: 'true');
      final isDone = await storage.read(key: 'onboarding_done');
      expect(isDone, equals('true'));
    });

    test('SecureStorage - should clear all data', () async {
      await storage.write(key: 'access_token', value: 'token');
      await storage.deleteAll();
      final token = await storage.read(key: 'access_token');
      expect(token, isNull);
    });

    test('SecureStorage - should check authentication', () async {
      await storage.write(key: 'access_token', value: 'valid-token');
      final token = await storage.read(key: 'access_token');
      final isAuth = token != null && token.isNotEmpty;
      expect(isAuth, isTrue);
    });
  });
}
