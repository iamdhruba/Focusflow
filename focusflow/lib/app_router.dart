import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/apps/providers/apps_provider.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/login_register_screen.dart';
import 'features/onboarding/screens/permission_pitch_screen.dart';
import 'features/onboarding/screens/permission_guide_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/apps/screens/select_apps_screen.dart';
import 'features/apps/screens/set_limit_screen.dart';
import 'features/blocker/screens/blocker_overlay_screen.dart';
import 'features/settings/screens/strict_mode_screen.dart';
import 'features/settings/screens/policy_about_screen.dart';

import 'features/auth/screens/forgot_password_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Listen to auth state so the router rebuilds on login/logout
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) async {
      final isAuth = authState.status == AuthStatus.authenticated;
      final isUnknown = authState.status == AuthStatus.unknown;

      // Still loading — don't redirect
      if (isUnknown) return null;

      final path = state.matchedLocation;
      final publicPaths = ['/', '/login', '/forgot-password', '/onboarding/pitch', '/onboarding/guide'];
      final isPublic = publicPaths.any((p) => path.startsWith(p));

      // Not authenticated → send to welcome
      if (!isAuth && !isPublic) return '/';

      // Authenticated → skip auth screens, go to dashboard
      if (isAuth && (path == '/' || path == '/login' || path == '/forgot-password')) {
        final onboardingDone = await SecureStorage.isOnboardingDone();
        return onboardingDone ? '/dashboard' : '/onboarding/pitch';
      }

      return null;
    },
    routes: [
      // ── Auth / Onboarding ──────────────────────────────────────────────
      GoRoute(
        path: '/',
        builder: (ctx, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (ctx, state) => const LoginRegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (ctx, state) => const ForgotPasswordScreen(),
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
          // Accept an existing AppPolicyModel passed as `extra`
          final policy = state.extra as AppPolicyModel? ??
              const AppPolicyModel(packageName: '', appName: 'Unknown App');
          return SetLimitScreen(policy: policy);
        },
      ),
      GoRoute(
        path: '/blocker',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return BlockerOverlayScreen(
            appName: extra?['appName'] as String? ?? 'This App',
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

    // 404 fallback
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('404 — Page not found',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ctx.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});
