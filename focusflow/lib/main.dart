import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:focusflow/core/services/api_service.dart';
import 'package:focusflow/core/services/local_policy_service.dart';
import 'package:focusflow/core/services/native_channel_service.dart';
import 'package:focusflow/core/services/screen_policy_service.dart';
import 'package:focusflow/core/services/screen_policy_sync.dart';
import 'package:focusflow/core/storage/local_database.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/app_router.dart';
import 'package:focusflow/features/apps/providers/apps_provider.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'localSyncTask') {
      try {
        final native = NativeChannelService();
        final localService = LocalPolicyService();
        final screenService = ScreenPolicyService();
        final db = LocalDatabase.instance;

        // 1. Get usage from system
        final usageMap = await native.getTodayUsageStats();

        // 2. Update local database
        for (var entry in usageMap.entries) {
          await localService.updateUsage(entry.key, entry.value);
        }

        // 3. Refresh native rules
        final policies = await localService.getPolicies();
        await native.updateBlockingRules(policies);

        // 4. Phase 3: push pending screen-policy deltas to the server so a
        // fresh install post-wipe can recover via the existing
        // `getScreenPolicies()` GET. Runs in this background isolate so
        // offline edits accumulated while the app was closed still get
        // promoted to the server on the next WorkManager sweep.
        try {
          await performScreenPolicySync(
            db: db,
            local: localService,
            postSync: (payload) => screenService.syncScreenPolicies(payload),
          );
        } catch (e) {
          debugPrint('Background screen-policy sync error: $e');
          // Don't fail the whole task — app-level sync already succeeded.
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

  // ── Environment + API client setup ──────────────────────────────────────────
  // Dotenv must be loaded BEFORE ApiService().init() because
  // ApiConstants.baseUrl reads dotenv.env['API_BASE_URL'] / ['APP_ENV'].
  // If .env is missing in dev we log a warning and continue — the
  // production path inside ApiConstants.baseUrl still throws a StateError
  // when APP_ENV=production and the URL is empty.
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('dotenv.load failed (missing .env?): $e');
  }
  try {
    ApiService().init();
  } catch (e) {
    debugPrint('ApiService.init failed: $e');
  }

  // ── Register WorkManager local sync ─────────────────────────────────────────
  if (!kIsWeb) {
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        'localSyncTask',
        'localSyncTask',
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
        ),
      );
    } catch (e) {
      debugPrint('Workmanager init failed: $e');
    }

    // Fix 4 (Dart side): recover from cold-launch race when native invokes
    // onAppBlocked before Dart's listener was attached. Kotlin caches the
    // package in initialBlockedPackage; pull it now before runApp.
    try {
      final blockedPkg = await NativeChannelService().getInitialBlockedApp();
      if (blockedPkg != null && blockedPkg.isNotEmpty) {
        pendingBlockedPackageOnLaunch = blockedPkg;
      }
      // Phase 1: same recovery pattern for the per-screen block details.
      final blockedScreen = await NativeChannelService().getInitialBlockedScreen();
      if (blockedScreen != null && blockedScreen.isNotEmpty) {
        pendingBlockedScreenOnLaunch = blockedScreen;
      }
      final blockedScreenFriendly =
          await NativeChannelService().getInitialBlockedScreenFriendly();
      if (blockedScreenFriendly != null && blockedScreenFriendly.isNotEmpty) {
        pendingBlockedScreenFriendlyOnLaunch = blockedScreenFriendly;
      }
    } catch (e) {
      debugPrint('getInitialBlockedApp failed: $e');
    }
  }

  runApp(const ProviderScope(child: FocusFlowApp()));
}

/// Fix 4: package that triggered a blocked-app cold launch. Resolved once
/// on first frame by FocusFlowApp.
String? pendingBlockedPackageOnLaunch;

/// Phase 1: per-screen block key (e.g. "reels") queued for cold-launch recovery.
String? pendingBlockedScreenOnLaunch;

/// Phase 1: friendly name (e.g. "Reels") queued for cold-launch recovery.
String? pendingBlockedScreenFriendlyOnLaunch;

class FocusFlowApp extends ConsumerWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Initialize native channel listener for blocking events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NativeChannelService().init(
        onAppBlocked: (args) {
          // args carries: packageName, and (Phase 1) screenKey + screenFriendly
          final pkg = args['packageName'] as String?;
          if (pkg == null) return;
          final apps = ref.read(appsProvider).policies;
          final app = apps.where((p) => p.packageName == pkg).firstOrNull;
          final appName = app?.appName ?? pkg;

          // Phase 1: pass through screen level info if native provided it
          final screenKey = args['screenKey'] as String?;
          final screenFriendly = args['screenFriendly'] as String?;
          router.push(
            '/blocker',
            extra: {
              'appName': appName,
              'screenKey': screenKey,
              'screenFriendly': screenFriendly,
            },
          );
        },
        // Phase 4: live per-screen dwell updates pushed by the Accessibility
        // service every ~5s while the user lingers on a matched screen.
        onScreenUsageUpdate: (args) {
          final pkg = args['packageName'] as String?;
          final screen = args['screenKey'] as String?;
          final ms = (args['usedMs'] as num?)?.toInt() ?? 0;
          if (pkg == null || screen == null) return;
          ref
              .read(appsProvider.notifier)
              .updateScreenUsage(pkg, screen, ms);
        },
      );

      // Fix 4 (Dart side): if we were launched by a blocked-app intent, the
      // listener above was attached AFTER the native invoke was already lost.
      // Pick up the cached package from main() and route to /blocker now.
      final coldLaunchPkg = pendingBlockedPackageOnLaunch;
      final coldLaunchScreen = pendingBlockedScreenOnLaunch;
      final coldLaunchScreenFriendly = pendingBlockedScreenFriendlyOnLaunch;
      if (coldLaunchPkg != null) {
        pendingBlockedPackageOnLaunch = null;
        pendingBlockedScreenOnLaunch = null;
        pendingBlockedScreenFriendlyOnLaunch = null;
        final apps = ref.read(appsProvider).policies;
        final app = apps.where((p) => p.packageName == coldLaunchPkg).firstOrNull;
        router.go(
          '/blocker',
          extra: {
            'appName': app?.appName ?? coldLaunchPkg,
            'screenKey': coldLaunchScreen,
            'screenFriendly': coldLaunchScreenFriendly,
          },
        );
      }
    });

    return MaterialApp.router(
      title: 'FocusFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }
}
