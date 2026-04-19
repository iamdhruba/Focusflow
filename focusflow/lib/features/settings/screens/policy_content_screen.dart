import 'package:flutter/material.dart';
import 'package:focusflow/core/theme/app_theme.dart';

class PolicyContentScreen extends StatelessWidget {
  final String title;
  final String content;

  const PolicyContentScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: AppColors.onSurface.withValues(alpha: 0.9),
                  ),
            ),
            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}

class PolicyData {
  static const String privacyPolicy = '''
FocusFlow ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our mobile application.

1. Data Collection
We collect minimal data necessary to provide focus-tracking and app-blocking features:
• Usage Statistics: To provide insights, we monitor which apps are used and for how long.
• Accessibility Service: We use this service strictly to identify when a restricted app is launched and to overlay a blocker screen. We do not record or transmit any personal on-screen content.
• Account Data: Your name, email, and preferences are synced with our secure servers to provide multi-device support.

2. Data Usage
Your data is used solely to:
• Enforce your personalized focus limits.
• Generate usage reports.
• Sync your settings across devices.

3. Data Protection
• We use industry-standard encryption (SSL/TLS) for data in transit.
• Passwords and PINs are hashed before being stored in our database.
• We NEVER sell, trade, or rent your personal data to third parties.

4. On-Device Processing
Whenever possible, data is processed locally on your device to ensure maximum privacy and low latency.

5. Your Rights
You can request a full deletion of your account and all associated data at any time via the Settings menu or by contacting support.
''';

  static const String termsOfService = '''
By using FocusFlow, you agree to the following terms and conditions:

1. Use of Service
FocusFlow is a productivity tool designed to help you manage screen time. You agree to use the application only for lawful purposes.

2. Accessibility Permissions
The app-blocking feature requires the use of Android Accessibility Services. By enabling this, you grant FocusFlow permission to detect foreground application changes.

3. Strict Mode Disclaimer
Strict Mode is a powerful feature designed to prevent you from bypassing your own limits. 
• If you forget your PIN while Strict Mode is active, you may be restricted from modifying your settings until the reset period expires or you use the email recovery flow.
• FocusFlow is not liable for any missed notifications or restricted access resulting from the limits YOU set.

4. Account Security
You are responsible for maintaining the confidentiality of your account credentials, including your password and Strict Mode PIN.

5. Modifications
We reserve the right to modify these terms at any time. Continued use of the app after such changes constitutes acceptance of the new terms.
''';

  static const String licenses = '''
FocusFlow is built using open-source software:

• Flutter (BSD-3-Clause)
• Riverpod (MIT)
• Dio (MIT)
• GoRouter (MIT)
• Mongoose (MIT)
• Bcrypt.js (MIT)

Detailed licenses for each package can be found in our repository and via the 'flutter oss licenses' tool.
''';
}
