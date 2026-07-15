import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:focusflow/main.dart' as app;
import 'package:focusflow/core/storage/secure_storage.dart';

/// End-to-end integration test for FocusFlow.
///
/// This test launches the real app, registers a new user against the running
/// backend, and verifies that the dashboard loads. It assumes the backend is
/// reachable via the API_BASE_URL configured in the app's .env file.
///
/// Run with:
///   flutter test integration_test/app_test.dart
///
/// To target a specific device:
///   flutter test -d <device_id> integration_test/app_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testPassword = 'TestPass123!';
  const testName = 'E2E Test';

  setUpAll(() async {
    // Ensure a clean auth state so the test always starts unauthenticated.
    await SecureStorage.clearAll();
  });

  testWidgets('register a new user and reach the dashboard', (WidgetTester tester) async {
    // Launch the app.
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Welcome screen -> tap "Get Started" to go to login/register.
    final getStarted = find.text('Get Started');
    expect(getStarted, findsOneWidget);
    await tester.tap(getStarted);
    await tester.pumpAndSettle();

    // Toggle to the registration form.
    final createAccountToggle = find.text("Don't have an account? Sign Up");
    expect(createAccountToggle, findsOneWidget);
    await tester.tap(createAccountToggle);
    await tester.pumpAndSettle();

    // Generate a unique email inside the test.
    final testEmail = 'e2e_${DateTime.now().millisecondsSinceEpoch}@focusflow.test';

    // Fill in the registration form using field order.
    final textFields = find.byType(TextFormField);
    expect(textFields, findsNWidgets(3));

    await tester.enterText(textFields.at(0), testName); // Full Name
    await tester.enterText(textFields.at(1), testEmail); // Email
    await tester.enterText(textFields.at(2), testPassword); // Password

    // Submit the form.
    final submitButton = find.widgetWithText(ElevatedButton, 'Create Account');
    await tester.tap(submitButton);

    // Wait for the network request and post-registration navigation.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // After registration the app navigates to the onboarding pitch.
    final grantPermissions = find.text('Grant Permissions');
    expect(grantPermissions, findsOneWidget);
    await tester.tap(grantPermissions);
    await tester.pumpAndSettle();

    // On the permission guide, skip the system permission dialogs.
    final skipForNow = find.text('Skip for now');
    expect(skipForNow, findsOneWidget);
    await tester.tap(skipForNow);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Verify the dashboard loaded.
    expect(find.textContaining("Today's Screen Time"), findsOneWidget);
    expect(find.text('No apps tracked yet'), findsOneWidget);

    // Verify the user can open the "Add App" flow.
    final addAppButton = find.text('Add App');
    expect(addAppButton, findsOneWidget);
  });
}
