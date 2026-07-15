import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/storage/secure_storage.dart';
import 'features/apps/providers/apps_provider.dart';
import 'features/onboarding/screens/permission_pitch_screen.dart';
import 'features/onboarding/screens/permission_guide_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/apps/screens/select_apps_screen.dart';
import 'features/apps/screens/set_limit_screen.dart';
import 'features/apps/screens/app_detail_screen.dart';
import 'features/blocker/screens/blocker_overlay_screen.dart';
import 'features/settings/screens/strict_mode_screen.dart';
import 'features/settings/screens/policy_about_screen.dart';

import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/login_register_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) async {
      final onboardingDone = await SecureStorage.isOnboardingDone();
      final path = state.matchedLocation;

      if (path == '/') {
        return onboardingDone ? '/dashboard' : '/welcome';
      }

      // Protect main features if onboarding not done
      if (!onboardingDone && (path.startsWith('/dashboard') || path.startsWith('/apps') || path.startsWith('/settings'))) {
        return '/welcome';
      }

      return null;
    },
    routes: [
      // ── Onboarding ─────────────────────────────────────────────────────
      GoRoute(
        path: '/welcome',
        builder: (ctx, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (ctx, state) => const LoginRegisterScreen(),
      ),
      GoRoute(
        path: '/onboarding/pitch',
        builder: (ctx, state) => const PermissionPitchScreen(),
      ),
      GoRoute(
        path: '/onboarding/guide',
        builder: (ctx, state) => const PermissionGuideScreen(),
      ),

      // ── Main App ───────────────────────────────────────────────────────
      GoRoute(
        path: '/dashboard',
        builder: (ctx, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/apps/select',
        builder: (ctx, state) => const SelectAppsScreen(),
      ),
      GoRoute(
        path: '/apps/set-limit',
        builder: (ctx, state) {
          final policy = state.extra as AppPolicyModel? ??
              const AppPolicyModel(packageName: '', appName: 'Unknown App');
          return SetLimitScreen(policy: policy);
        },
      ),
      GoRoute(
        path: '/apps/detail',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, String>? ??
              const {'packageName': '', 'appName': 'Unknown App'};
          return AppDetailScreen(
            packageName: extra['packageName'] ?? '',
            appName: extra['appName'] ?? 'Unknown App',
          );
        },
      ),
      GoRoute(
        path: '/blocker',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return BlockerOverlayScreen(
            appName: extra?['appName'] as String? ?? 'This App',
            screenName: extra?['screenFriendly'] as String?,
            onGoBack: () => ctx.pop(),
          );
        },
      ),

      // ── Settings ───────────────────────────────────────────────────────
      GoRoute(
        path: '/settings/strict',
        builder: (ctx, state) => const StrictModeScreen(),
      ),
      GoRoute(
        path: '/settings/about',
        builder: (ctx, state) => const PolicyAboutScreen(),
      ),
    ],

    errorBuilder: (ctx, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('404 — Page not found', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ctx.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
});
