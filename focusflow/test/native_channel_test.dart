import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:focusflow/core/services/native_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Channel Tests', () {
    final nativeService = NativeChannelService();

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.focusflow.app/usageStats'),
        (call) async {
          switch (call.method) {
            case 'getInstalledApps':
              return [
                {'packageName': 'com.example.app', 'appName': 'Test App'}
              ];
            case 'getTodayUsage':
              return {'com.example.app': 3600000};
            default:
              return null;
          }
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.focusflow.app/permissions'),
        (call) async {
          switch (call.method) {
            case 'hasAccessibilityPermission':
              return true;
            case 'hasUsageStatsPermission':
              return true;
            case 'hasOverlayPermission':
              return true;
            case 'isDeviceAdminActive':
              return true;
            default:
              return null;
          }
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.focusflow.app/blocking'),
        (call) async {
          if (call.method == 'updateBlockingRules') {
            return null;
          }
          return null;
        },
      );
    });

    test('getInstalledApps should return app list', () async {
      final apps = await nativeService.getInstalledApps();
      expect(apps, isA<List>());
      expect(apps.isNotEmpty, isTrue);
      expect(apps[0]['packageName'], equals('com.example.app'));
    });

    test('getTodayUsageStats should return usage map', () async {
      final usage = await nativeService.getTodayUsageStats();
      expect(usage, isA<Map<String, int>>());
      expect(usage['com.example.app'], equals(3600000));
    });

    test('updateBlockingRules should accept policies', () async {
      await nativeService.updateBlockingRules([]);
      expect(true, isTrue);
    });

    test('hasAccessibilityPermission should return bool', () async {
      final enabled = await nativeService.hasAccessibilityPermission();
      expect(enabled, isA<bool>());
      expect(enabled, isTrue);
    });

    test('hasUsageStatsPermission should return bool', () async {
      final enabled = await nativeService.hasUsageStatsPermission();
      expect(enabled, isA<bool>());
      expect(enabled, isTrue);
    });

    test('hasOverlayPermission should return bool', () async {
      final enabled = await nativeService.hasOverlayPermission();
      expect(enabled, isA<bool>());
      expect(enabled, isTrue);
    });

    test('isDeviceAdminActive should return bool', () async {
      final enabled = await nativeService.isDeviceAdminActive();
      expect(enabled, isA<bool>());
      expect(enabled, isTrue);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.focusflow.app/usageStats'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.focusflow.app/permissions'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.focusflow.app/blocking'), null);
    });
  });
}
