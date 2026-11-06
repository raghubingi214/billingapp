import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/inventory/domain/inventory_repository.dart';
import 'package:smart_billing/features/inventory/presentation/inventory_screen.dart';

class FakeInventoryRepository implements InventoryRepository {
  int counts = 0, histories = 0;
  @override
  Future<List<StockOutlet>> outlets(String organizationId) async => [
    const StockOutlet('outlet', 'Main shop'),
  ];
  @override
  Future<List<StockPosition>> positions(
    String org,
    String outlet,
    int offset, {
    bool lowOnly = false,
  }) async => [const StockPosition('rice', 'Rice', 'kg', '10', 1)];
  @override
  Future<List<StockMovement>> movements(
    String org,
    String outlet,
    String product,
    int offset,
  ) async {
    histories++;
    return [const StockMovement('10', 'Opening count', '2026-11-05T00:00:00Z')];
  }

  @override
  Future<void> count(
    String requestId,
    String org,
    String outlet,
    StockPosition position,
    String quantity,
    String reason,
  ) async {
    counts++;
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeInventoryRepository repository, {
    bool owner = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [inventoryRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: InventoryScreen(
            organizationId: 'org',
            canCount: owner,
            canReadHistory: owner,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cashier sees balances without owner count or movement actions', (
    tester,
  ) async {
    final repository = FakeInventoryRepository();
    await open(tester, repository, owner: false);
    expect(find.text('10 kg on hand'), findsOneWidget);
    expect(find.byTooltip('Count stock'), findsNothing);
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(repository.histories, 0);
  });
  testWidgets('invalid count precision and missing reason never post', (
    tester,
  ) async {
    final repository = FakeInventoryRepository();
    await open(tester, repository);
    await tester.tap(find.byTooltip('Count stock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '1.0001');
    await tester.tap(find.text('Post count'));
    await tester.pumpAndSettle();
    expect(find.text('Use up to three decimals'), findsOneWidget);
    expect(find.text('Enter a reason (3+ characters)'), findsOneWidget);
    expect(repository.counts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  testWidgets('owner can view movement history', (tester) async {
    final repository = FakeInventoryRepository();
    await open(tester, repository);
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(repository.histories, 1);
    expect(find.textContaining('Opening count'), findsOneWidget);
  });
}
