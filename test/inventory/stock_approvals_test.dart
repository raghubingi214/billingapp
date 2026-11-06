import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/inventory/domain/stock_approval_repository.dart';
import 'package:smart_billing/features/inventory/presentation/inventory_screen.dart';
import 'package:smart_billing/features/inventory/presentation/stock_approvals_screen.dart';
import 'inventory_test.dart' show FakeInventoryRepository;

class FakeApprovals implements StockApprovalRepository {
  int requests = 0, reviews = 0;
  bool? decision;
  @override
  Future<void> request(
    String key,
    String org,
    String outlet,
    String product,
    int version,
    String quantity,
    String reason,
  ) async {
    expect(product, 'rice');
    expect(version, 1);
    expect(quantity, '12');
    requests++;
  }

  @override
  Future<List<StockApproval>> page(String org, int offset) async => [
    StockApproval(
      'request',
      'Rice',
      'Main shop',
      '12',
      'Recount',
      reviews == 0 ? 'pending' : 'approved',
    ),
  ];
  @override
  Future<void> review(String key, String org, String id, bool approve) async {
    reviews++;
    decision = approve;
  }
}

void main() {
  testWidgets('manager submits approval without posting stock directly', (
    tester,
  ) async {
    final stock = FakeInventoryRepository(), approvals = FakeApprovals();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(stock),
          stockApprovalRepositoryProvider.overrideWithValue(approvals),
        ],
        child: const MaterialApp(
          home: InventoryScreen(
            organizationId: 'org',
            canCount: false,
            canReadHistory: true,
            canRequest: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Request stock count'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '12');
    await tester.enterText(find.byType(TextFormField).at(1), 'Recount');
    await tester.tap(find.text('Submit count'));
    await tester.pumpAndSettle();
    expect(approvals.requests, 1);
    expect(stock.counts, 0);
  });
  testWidgets('owner must confirm approval and cannot approve twice', (
    tester,
  ) async {
    final approvals = FakeApprovals();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockApprovalRepositoryProvider.overrideWithValue(approvals),
        ],
        child: const MaterialApp(
          home: StockApprovalsScreen(organizationId: 'org', canReview: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(approvals.reviews, 0);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(approvals.reviews, 1);
    expect(approvals.decision, true);
    expect(find.text('Approve'), findsNothing);
  });
  testWidgets('manager history has no approval actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockApprovalRepositoryProvider.overrideWithValue(FakeApprovals()),
        ],
        child: const MaterialApp(
          home: StockApprovalsScreen(organizationId: 'org', canReview: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Counted 12 · pending'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });
}
