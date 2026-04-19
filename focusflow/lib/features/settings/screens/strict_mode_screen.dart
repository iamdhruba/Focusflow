import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/features/auth/providers/auth_provider.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';
import 'package:focusflow/shared/widgets/glass_card.dart';
import 'package:focusflow/core/services/auth_service.dart';

/// Screen 8: Strict Mode Settings
class StrictModeScreen extends ConsumerStatefulWidget {
  const StrictModeScreen({super.key});
  @override
  ConsumerState<StrictModeScreen> createState() => _StrictModeScreenState();
}

class _StrictModeScreenState extends ConsumerState<StrictModeScreen> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPinInput = false;
  bool _isDisabling = false;
  String? _pinError;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _showForgotPINDialog() async {
    setState(() => _isDisabling = true);
    final result = await AuthService().forgotPIN();
    setState(() => _isDisabling = false);

    if (!mounted) return;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Failed to request reset code')));
      return;
    }

    final codeCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Strict PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('A 6-digit reset code has been sent to your registered email address.'),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Reset Code', hintText: '6-digit code'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPinCtrl,
              decoration: const InputDecoration(labelText: 'New PIN', hintText: 'Min 4 digits'),
              keyboardType: TextInputType.number,
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (codeCtrl.text.isEmpty || newPinCtrl.text.length < 4) return;
              final res = await AuthService().resetPIN(
                code: codeCtrl.text.trim(),
                newPin: newPinCtrl.text,
              );
              if (res.success) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.message ?? 'PIN reset!')));
                }
                // Refresh user state
                await ref.read(authProvider.notifier).login(
                  email: ref.read(authProvider).user?['email'] ?? '',
                  password: '', 
                );
              }
            },
            child: const Text('Reset PIN'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableStrictMode() async {
    if (_pinCtrl.text.length < 4) {
      setState(() => _pinError = 'PIN must be at least 4 digits');
      return;
    }
    if (_pinCtrl.text != _confirmCtrl.text) {
      setState(() => _pinError = 'PINs do not match');
      return;
    }
    setState(() => _pinError = null);
    final ok = await ref.read(authProvider.notifier).updateStrictMode(
          enabled: true, pin: _pinCtrl.text);
    if (ok && mounted) {
      setState(() => _showPinInput = false);
      _pinCtrl.clear(); _confirmCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Strict Mode enabled'), backgroundColor: AppColors.tertiary));
    }
  }

  Future<void> _disableStrictMode() async {
    if (_pinCtrl.text.isEmpty) {
      setState(() => _pinError = 'Enter your PIN');
      return;
    }
    setState(() { _isDisabling = true; _pinError = null; });
    
    // In our logic, the first PIN entry starts the cooldown,
    // and the second one (after 24h) actually disables it.
    final ok = await ref.read(authProvider.notifier).updateStrictMode(
        enabled: false, pin: _pinCtrl.text);
    
    setState(() => _isDisabling = false);
    
    if (ok && mounted) {
      final auth = ref.read(authProvider);
      if (auth.user?['strictModeDisableRequestAt'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('24-hour cooldown started. Come back tomorrow.'),
            backgroundColor: AppColors.primary,
          ),
        );
      } else {
        setState(() => _showPinInput = false);
      }
      _pinCtrl.clear();
    } else if (mounted) {
      final err = ref.read(authProvider).error;
      setState(() => _pinError = err ?? 'Incorrect PIN or Cooldown Active');
    }
  }

  String _formatCooldown(String? isoDate) {
    if (isoDate == null) return '';
    final date = DateTime.parse(isoDate).toLocal();
    final unlockDate = date.add(const Duration(hours: 24));
    final diff = unlockDate.difference(DateTime.now());
    
    if (diff.isNegative) return 'Ready to disable';
    return '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final strictMode = auth.strictMode;
    final cooldownStart = auth.user?['strictModeDisableRequestAt'] as String?;
    final isCooldownActive = cooldownStart != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Strict Mode'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        actions: [
          TextButton(
            onPressed: () => context.push('/settings/about'),
            child: const Text('About'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Daily Focus Goal ──────────────────────────────────────────────────
            Text('Daily Focus Goal', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total allowed usage',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      Text(
                        '${auth.dailyGoalMinutes ~/ 60}h ${auth.dailyGoalMinutes % 60}m',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.primaryFixed,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.1),
                    ),
                    child: Slider(
                      value: auth.dailyGoalMinutes.toDouble(),
                      min: 30,
                      max: 480,
                      divisions: 15, // Every 30 mins
                      onChanged: (v) {
                        ref.read(authProvider.notifier).updateStrictMode(
                          dailyGoalMinutes: v.toInt(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            Text('Security Settings', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: strictMode ? AppColors.error.withValues(alpha: 0.12) : AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(strictMode ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: strictMode ? AppColors.error : AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Strict Mode', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          isCooldownActive
                              ? 'Cooldown Active — ${_formatCooldown(cooldownStart)}'
                              : strictMode
                                  ? 'Active — uninstallation is protected by PIN'
                                  : 'Inactive — app can be uninstalled freely',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isCooldownActive ? AppColors.primary : AppColors.onSurfaceVariant,
                                fontWeight: isCooldownActive ? FontWeight.w600 : FontWeight.normal,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: strictMode ? AppColors.errorContainer : AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(strictMode ? 'ON' : 'OFF',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: strictMode ? AppColors.error : AppColors.primary,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            Text('What Strict Mode does', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            ...[
              (Icons.admin_panel_settings_rounded, 'Prevents FocusFlow from being uninstalled without a PIN'),
              (Icons.settings_applications_rounded, 'Blocks access to Android Settings in the restricted list'),
              (Icons.lock_clock_rounded, 'Requires a 24-hour cooldown before disabling'),
            ].map((item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(item.$1, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(item.$2, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4))),
                ],
              ),
            )),

            const SizedBox(height: AppSpacing.xl),

            if (_showPinInput) ...[
              TextField(
                controller: _pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: strictMode ? 'Enter current PIN to disable' : 'Create a PIN (min 4 digits)',
                  errorText: _pinError,
                  prefixIcon: const Icon(Icons.pin_rounded),
                ),
              ),
              if (!strictMode) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
                    prefixIcon: Icon(Icons.pin_rounded),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              GradientButton(
                label: strictMode ? 'Disable Strict Mode' : 'Enable Strict Mode',
                isLoading: _isDisabling || auth.isLoading,
                onPressed: strictMode ? _disableStrictMode : _enableStrictMode,
              ),
              const SizedBox(height: AppSpacing.sm),
              GradientButton(
                label: 'Cancel',
                isSecondary: true,
                onPressed: () {
                  setState(() { _showPinInput = false; _pinError = null; });
                  _pinCtrl.clear(); _confirmCtrl.clear();
                },
              ),
              if (strictMode) ...[
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: _showForgotPINDialog,
                    child: Text(
                      'Forgot PIN?',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              GradientButton(
                label: strictMode ? 'Disable Strict Mode' : 'Enable Strict Mode',
                icon: strictMode ? Icons.lock_open_rounded : Icons.lock_rounded,
                onPressed: () => setState(() => _showPinInput = true),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            GradientButton(
              label: 'Sign Out',
              isSecondary: true,
              icon: Icons.logout_rounded,
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/');
              },
            ),
          ],
        ),
      ),
    );
  }
}
