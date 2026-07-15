import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';
import 'package:focusflow/shared/widgets/glass_card.dart';
import 'package:focusflow/core/services/native_channel_service.dart';

class StrictModeScreen extends ConsumerStatefulWidget {
  const StrictModeScreen({super.key});
  @override
  ConsumerState<StrictModeScreen> createState() => _StrictModeScreenState();
}

class _StrictModeScreenState extends ConsumerState<StrictModeScreen> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPinInput = false;
  bool _isProcessing = false;
  String? _pinError;
  bool _strictModeEnabled = false;
  bool _isAdminActive = false;

  final _native = NativeChannelService();

  @override
  void initState() {
    super.initState();
    _native.setSafeMode(true);
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final status = await _native.getStrictModeStatus();
    if (mounted) {
      setState(() {
        _strictModeEnabled = status;
      });
    }
    final admin = await _native.isDeviceAdminActive();
    if (mounted) {
      setState(() => _isAdminActive = admin);
    }
  }

  @override
  void dispose() {
    _native.setSafeMode(false);
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _enableStrictMode() async {
    if (!_isAdminActive) {
      setState(() => _pinError = 'Device Admin must be enabled first');
      return;
    }
    if (_pinCtrl.text.length < 4) {
      setState(() => _pinError = 'PIN must be at least 4 digits');
      return;
    }
    if (_pinCtrl.text != _confirmCtrl.text) {
      setState(() => _pinError = 'PINs do not match');
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _pinError = null;
    });

    final success = await _native.updateStrictMode(
      enabled: true,
      pin: _pinCtrl.text,
    );

    setState(() => _isProcessing = false);

    if (success && mounted) {
      setState(() {
        _showPinInput = false;
        _strictModeEnabled = true;
      });
      // Capture ScaffoldMessenger before the async gap so we don't regress
      // to `BuildContext` after `await` (which analyzers flag as risky).
      final messenger = ScaffoldMessenger.of(context);
      // Explicitly trigger native uninstall block
      await _native.setUninstallBlocked(true);
      _pinCtrl.clear();
      _confirmCtrl.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Strict Mode enabled'), backgroundColor: AppColors.tertiary));
    } else if (mounted) {
      setState(() => _pinError = 'Failed to enable Strict Mode');
    }
  }

  Future<void> _disableStrictMode() async {
    if (_pinCtrl.text.isEmpty) {
      setState(() => _pinError = 'Enter your PIN');
      return;
    }

    setState(() {
      _isProcessing = true;
      _pinError = null;
    });

    final success = await _native.updateStrictMode(
      enabled: false,
      pin: _pinCtrl.text,
    );

    setState(() => _isProcessing = false);

    if (success && mounted) {
      setState(() {
        _showPinInput = false;
        _strictModeEnabled = false;
      });
      // Capture ScaffoldMessenger before the async gap so we don't regress
      // to `BuildContext` after `await` (which analyzers flag as risky).
      final messenger = ScaffoldMessenger.of(context);
      // Explicitly disable native uninstall block
      await _native.setUninstallBlocked(false);
      _pinCtrl.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Strict Mode disabled'), backgroundColor: AppColors.primary));
    } else if (mounted) {
      setState(() => _pinError = 'Incorrect PIN or 24h Lock active');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Strict Mode'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Security Settings', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: _strictModeEnabled ? AppColors.error.withValues(alpha: 0.12) : AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(_strictModeEnabled ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: _strictModeEnabled ? AppColors.error : AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Strict Mode', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          _strictModeEnabled
                              ? 'Active — protected by 24h lock'
                              : 'Inactive — protection is disabled',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _strictModeEnabled ? AppColors.errorContainer : AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(_strictModeEnabled ? 'ON' : 'OFF',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: _strictModeEnabled ? AppColors.error : AppColors.primary,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),

            if (!_isAdminActive && !_strictModeEnabled) ...[
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Device Admin permission is REQUIRED to prevent app uninstallation.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _native.requestDeviceAdmin();
                        _checkStatus();
                      },
                      child: const Text('Enable'),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            Text('What Strict Mode does', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            ...[
              (Icons.admin_panel_settings_rounded, 'Prevents FocusFlow from being uninstalled'),
              (Icons.settings_applications_rounded, 'Blocks access to Android Settings'),
              (Icons.lock_clock_rounded, 'Requires a 24-hour wait before disabling'),
            ].map<Widget>((item) => Padding(
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
                  labelText: _strictModeEnabled ? 'Enter PIN to disable' : 'Create a PIN (min 4 digits)',
                  errorText: _pinError,
                  prefixIcon: const Icon(Icons.pin_rounded),
                ),
              ),
              if (!_strictModeEnabled) ...[
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
                label: _strictModeEnabled ? 'Disable Strict Mode' : 'Enable Strict Mode',
                isLoading: _isProcessing,
                onPressed: _strictModeEnabled ? _disableStrictMode : _enableStrictMode,
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
            ] else ...[
              GradientButton(
                label: _strictModeEnabled ? 'Disable Strict Mode' : 'Enable Strict Mode',
                icon: _strictModeEnabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                onPressed: () => setState(() => _showPinInput = true),
              ),
            ],
            
            const SizedBox(height: AppSpacing.xxxl),
            Text(
              'Strict mode is local to this device. If you forget your PIN, you must wait 24 hours to attempt a reset (via device settings if available).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
