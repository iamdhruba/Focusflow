import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusflow/features/apps/providers/apps_provider.dart';
import 'package:focusflow/features/apps/screens/app_detail_screen.dart';

void main() {
  testWidgets(
    'AppDetailScreen renders all Instagram sections and reflects the active rule on load',
    (tester) async {
      final reels = ScreenPolicyModel.fromMap({
        'packageName': 'com.instagram.android',
        'screenKey': 'reels',
        'friendlyName': 'Reels',
        'timeLimitMinutes': 15,
        'isActive': true,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appsProvider.overrideWith((ref) {
              final notifier =
                  _TestAppsNotifier(initialScreenPolicies: [reels]);
              notifier.load();
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: AppDetailScreen(
              packageName: 'com.instagram.android',
              appName: 'Instagram',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scaffold + AppBar present
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Specific Sections'), findsOneWidget);

      // Instagram has 3 supported sections per kSupportedScreens
      expect(find.text('Reels'), findsOneWidget);
      expect(find.text('Stories'), findsOneWidget);
      expect(find.text('Explore / Search'), findsOneWidget);

      // The seeded Reels rule renders its detail label
      expect(find.text('15m per day'), findsOneWidget);

      // Three Switches per supported section
      expect(find.byType(Switch), findsNWidgets(3));

      // The seeded Reels rule is active → slider present
      expect(find.byType(Slider), findsWidgets);
    },
  );

  testWidgets(
    'TikTok detail screen renders three Switches and three catalog rows when no rules loaded',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appsProvider.overrideWith((ref) {
              final notifier = _TestAppsNotifier(initialScreenPolicies: const []);
              notifier.load();
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: AppDetailScreen(
              packageName: 'com.zhiliaoapp.musically',
              appName: 'TikTok',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TikTok catalog has 3 entries (fyp, search, live).
      expect(find.text('For You (FYP)'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);

      // One Switch per catalog row.
      expect(find.byType(Switch), findsNWidgets(3));

      // No active rules → no sliders expected (slider only appears when isActive).
      expect(find.byType(Slider), findsNothing);

      // No active rules → no progress bars expected.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'AppDetailScreen shows live progress bar for an active rule with native usage data',
    (tester) async {
      // Reels: 30 min limit, 10 min used today → ~33% of the cap.
      final reels = ScreenPolicyModel.fromMap({
        'packageName': 'com.instagram.android',
        'screenKey': 'reels',
        'friendlyName': 'Reels',
        'timeLimitMinutes': 30,
        'isActive': true,
        'todayUsageMs': 10 * 60 * 1000,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appsProvider.overrideWith((ref) {
              final notifier =
                  _TestAppsNotifier(initialScreenPolicies: [reels]);
              notifier.load();
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: AppDetailScreen(
              packageName: 'com.instagram.android',
              appName: 'Instagram',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly one progress bar (only Reels is active+hasSlidingCap).
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // The progress bar shows roughly 33% of the cap.
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, isNotNull);
      expect(bar.value! > 0.30 && bar.value! < 0.36, isTrue,
          reason:
              'Expected ~0.33 progress (10 of 30) but got ${bar.value}');

      // Label matches the seeded used/limit.
      expect(find.text('10m of 30m'), findsOneWidget);
    },
  );

  testWidgets(
    'AppDetailScreen shows no progress bar when rule is full-block (limitMinutes = 0)',
    (tester) async {
      // Reels: Active but timeLimitMinutes = 0 → full block, no progress.
      final reels = ScreenPolicyModel.fromMap({
        'packageName': 'com.instagram.android',
        'screenKey': 'reels',
        'friendlyName': 'Reels',
        'timeLimitMinutes': 0,
        'isActive': true,
        'todayUsageMs': 5 * 60 * 1000, // dwell before being blocked
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appsProvider.overrideWith((ref) {
              final notifier =
                  _TestAppsNotifier(initialScreenPolicies: [reels]);
              notifier.load();
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: AppDetailScreen(
              packageName: 'com.instagram.android',
              appName: 'Instagram',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Full-block has no progress to render.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // "Full block" is rendered in two places for full-block rules:
      //   1. The status subtitle under the emoji/title row
      //   2. The toggle pill in the slider section header
      expect(find.text('Full block'), findsNWidgets(2));
    },
  );
}

/// A no-I/O notifier used only inside tests. Inherits from AppsNotifier so
/// the provider stays the same shape; overrides the only async methods
/// `load()` and `upsertScreenPolicy()` to skip disk + backend I/O.
class _TestAppsNotifier extends AppsNotifier {
  _TestAppsNotifier({List<ScreenPolicyModel> initialScreenPolicies = const []}) {
    state = state.copyWith(screenPolicies: initialScreenPolicies);
  }

  @override
  Future<void> load() async {
    state = state.copyWith(isLoading: false);
  }

  @override
  Future<bool> upsertScreenPolicy(ScreenPolicyModel policy) async {
    final updated = [
      ...state.screenPolicies.where((p) =>
          !(p.packageName == policy.packageName &&
              p.screenKey == policy.screenKey)),
      policy,
    ];
    state = state.copyWith(screenPolicies: updated);
    return true;
  }
}
