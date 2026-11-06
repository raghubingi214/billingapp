import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/inventory/domain/inventory_repository.dart';
import 'package:smart_billing/features/inventory/presentation/stock_history_sheet.dart';

void main() {
  testWidgets('older movement retry retains loaded entries and offset', (
    tester,
  ) async {
    final offsets = <int>[];
    var failNext = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockHistorySheet(
            product: 'Rice',
            unit: 'kg',
            loadPage: (offset) async {
              offsets.add(offset);
              if (offset == 0) {
                return List.generate(
                  50,
                  (i) =>
                      StockMovement('1', 'Movement $i', '2026-11-05T00:00:00Z'),
                );
              }
              if (failNext) {
                failNext = false;
                throw Exception('Network');
              }
              return [
                const StockMovement(
                  '-2',
                  'Older count',
                  '2026-11-04T00:00:00Z',
                ),
              ];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Load older movements'), 500);
    await tester.tap(find.text('Load older movements'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to load movement history. Retry.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Unable to load movement history. Retry.'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('All movements loaded'), 200);
    expect(find.textContaining('Older count'), findsOneWidget);
    expect(offsets, [0, 50, 50]);
  });
}
