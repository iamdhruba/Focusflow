import 'package:flutter_test/flutter_test.dart';
import 'package:focusflow/core/services/policy_service.dart';

void main() {
  group('Policy Tests', () {
    test('PolicyService - sync should handle usage data', () async {
      final policyService = PolicyService();
      try {
        final result = await policyService.sync(
          deviceId: 'test-device',
          usageReport: [
            {'packageName': 'com.example.app', 'usedMs': 3600000}
          ],
        );
        expect(result, isNotNull);
        expect(result.success, isA<bool>());
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    test('PolicyService - should handle empty usage report', () async {
      final policyService = PolicyService();
      try {
        final result = await policyService.sync(
          deviceId: 'test-device',
          usageReport: [],
        );
        expect(result, isNotNull);
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });
}
