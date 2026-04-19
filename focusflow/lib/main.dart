import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';
import 'package:focusflow/core/constants/api_constants.dart';
import 'package:focusflow/core/services/api_service.dart';
import 'package:focusflow/core/services/policy_service.dart';
import 'package:focusflow/core/services/native_channel_service.dart';
import 'package:focusflow/core/storage/secure_storage.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/app_router.dart';

/// WorkManager background callback — runs in an isolate.
/// This is the 15-minute sync task registered at startup.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == ApiConstants.syncTaskName) {
      try {
        await dotenv.load(fileName: '.env');
        ApiService().init();
        final native = NativeChannelService();
        final policyService = PolicyService();

        final usageMap = await native.getTodayUsageStats();
        final deviceId = await SecureStorage.getUserId() ?? 'unknown';
        final usageReport = usageMap.entries
            .map((e) => {'packageName': e.key, 'usedMs': e.value})
            .toList();

        final result = await policyService.sync(
          deviceId: deviceId,
          usageReport: usageReport,
        );

        if (result.success && result.policies != null) {
          await native.updateBlockingRules(result.policies!);
        }
        return Future.value(true);
      } catch (e) {
        debugPrint('Background sync error: $e');
        return Future.value(false);
      }
    }
    return Future.value(false);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Load environment variables ─────────────────────────────────────────────
  await dotenv.load(fileName: '.env');

  // ── Initialize API client ──────────────────────────────────────────────────
  ApiService().init();

  // ── Register WorkManager background sync (every 15 min) ───────────────────
  if (!kIsWeb) {
    try {
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        ApiConstants.syncTaskName,
        ApiConstants.syncTaskName,
        tag: ApiConstants.syncTaskTag,
        frequency: Duration(minutes: ApiConstants.syncIntervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('Workmanager init failed: $e');
    }
  }

  runApp(const ProviderScope(child: FocusFlowApp()));
}

class FocusFlowApp extends ConsumerWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'FocusFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
