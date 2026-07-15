import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusflow/shared/widgets/gradient_button.dart';
import 'package:focusflow/shared/widgets/glass_card.dart';

void main() {
  group('Widget Tests', () {
    testWidgets('GradientButton should render with label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GradientButton(
              label: 'Test Button',
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('GradientButton should handle loading state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GradientButton(
              label: 'Loading',
              isLoading: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('GradientButton should handle disabled state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GradientButton(
              label: 'Disabled',
              onPressed: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('GlassCard should render child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCard(
              child: Text('Glass Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Glass Content'), findsOneWidget);
    });
  });
}
