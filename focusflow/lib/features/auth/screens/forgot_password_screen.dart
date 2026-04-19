import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:focusflow/core/theme/app_theme.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';
import 'package:focusflow/core/services/auth_service.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  
  bool _codeSent = false;
  bool _isLoading = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _emailCtrl.dispose(); _codeCtrl.dispose(); _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestToken() async {
    if (_emailCtrl.text.isEmpty) return;
    setState(() { _isLoading = true; _error = null; });
    
    final result = await AuthService().forgotPassword(_emailCtrl.text.trim());
    
    setState(() {
      _isLoading = false;
      if (result.success) {
        _codeSent = true;
        _message = "Reset token sent! Please check your email inbox.";
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _resetPassword() async {
    if (_codeCtrl.text.isEmpty || _passCtrl.text.length < 8) return;
    setState(() { _isLoading = true; _error = null; });
    
    final result = await AuthService().resetPassword(
      token: _codeCtrl.text.trim(),
      newPassword: _passCtrl.text,
    );
    
    setState(() {
      _isLoading = false;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully! Please login.')),
        );
        context.go('/login');
      } else {
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_codeSent ? 'Reset\nyour password.' : 'Forgot\npassword?',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -1.5)),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _codeSent 
                  ? 'Enter the token you received and your new password.'
                  : 'Enter your email address and we\'ll send you a recovery token.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xxxl),

              if (!_codeSent) ...[
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                GradientButton(
                  label: 'Send Recovery Token',
                  isLoading: _isLoading,
                  onPressed: _requestToken,
                ),
              ] else ...[
                TextFormField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Recovery Token',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                GradientButton(
                  label: 'Reset Password',
                  isLoading: _isLoading,
                  onPressed: _resetPassword,
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              if (_message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_message!, style: const TextStyle(color: AppColors.tertiary, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
