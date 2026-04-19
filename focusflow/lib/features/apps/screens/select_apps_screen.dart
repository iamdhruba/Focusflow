import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/features/apps/providers/apps_provider.dart';

/// Screen 5: Select Apps
/// Shows all installed apps; user taps to add a blocking policy.
class SelectAppsScreen extends ConsumerStatefulWidget {
  const SelectAppsScreen({super.key});

  @override
  ConsumerState<SelectAppsScreen> createState() => _SelectAppsScreenState();
}

class _SelectAppsScreenState extends ConsumerState<SelectAppsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appsProvider.notifier).loadInstalledApps());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(appsProvider);
    final existingPackages = apps.policies.map((p) => p.packageName).toSet();

    final filtered = apps.installedApps.where((a) {
      return a.appName.toLowerCase().contains(_query.toLowerCase()) ||
          a.packageName.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Select Apps'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.md),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.onSurfaceVariant),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          // App count
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
            child: Row(
              children: [
                Text('${filtered.length} apps found',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),

          // List
          Expanded(
            child: apps.installedApps.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxxl),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (ctx, i) {
                      final app = filtered[i];
                      final alreadyAdded =
                          existingPackages.contains(app.packageName);
                      return _InstalledAppTile(
                        app: app,
                        alreadyAdded: alreadyAdded,
                        onTap: () {
                          context.push('/apps/set-limit',
                              extra: AppPolicyModel(
                                packageName: app.packageName,
                                appName: app.appName,
                              ));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InstalledAppTile extends StatelessWidget {
  final InstalledApp app;
  final bool alreadyAdded;
  final VoidCallback onTap;

  const _InstalledAppTile({
    required this.app,
    required this.alreadyAdded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alreadyAdded ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: alreadyAdded ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: AppRadius.cardRadius,
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              // App icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.primaryFixed,
                      AppColors.secondaryFixed,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(
                  child: Text(
                    app.appName.isNotEmpty ? app.appName[0].toUpperCase() : 'A',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.appName,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(app.packageName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (alreadyAdded)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text('Added',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.primary)),
                )
              else
                const Icon(Icons.add_circle_rounded,
                    color: AppColors.primary, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
