import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/platform/domain/platform_plan_repository.dart';
import 'package:smart_billing/features/platform/presentation/platform_plans_screen.dart';

class _Plans implements PlatformPlanRepository {
  int drafts = 0;
  @override
  Future<void> createDraft(String requestId, Map<String, dynamic> data) async {
    drafts++;
  }

  @override
  Future<List<Map<String, dynamic>>> page(int offset) async => [
    {
      'name': 'Starter draft',
      'active': false,
      'price_inr': 199,
      'billing_interval': 'month',
      'monthly_invoice_limit': 1000,
      'staff_limit': 2,
      'location_limit': 1,
    },
  ];
}

void main() {
  testWidgets('invalid draft never reaches backend', (tester) async {
    final plans = _Plans();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformPlanRepositoryProvider.overrideWithValue(plans)],
        child: const MaterialApp(home: PlatformPlanDraftScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save inactive draft'));
    await tester.tap(find.text('Save inactive draft'));
    await tester.pumpAndSettle();
    expect(plans.drafts, 0);
    expect(find.text('Enter a name up to 120 characters'), findsOneWidget);
  });
  testWidgets('plan catalog labels drafts without activation actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformPlanRepositoryProvider.overrideWithValue(_Plans())],
        child: const MaterialApp(home: PlatformPlansScreen(userId: 'admin')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Starter draft'), findsOneWidget);
    expect(find.text('Inactive draft · ₹199 / month'), findsOneWidget);
    expect(find.text('Activate'), findsNothing);
    await tester.tap(find.text('Starter draft'));
    await tester.pumpAndSettle();
    expect(find.text('Users including owner'), findsOneWidget);
  });
}
