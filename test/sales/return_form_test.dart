import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/sales/domain/return_repository.dart';
import 'package:smart_billing/features/sales/presentation/return_screen.dart';

class FakeReturnRepository implements ReturnRepository {
  int calls = 0;
  @override
  Future<void> post(
    String key,
    String org,
    String invoice,
    String reason,
    List<Map<String, Object?>> items,
  ) async {
    calls++;
  }
}

void main() {
  testWidgets('return form rejects quantity above net sold', (tester) async {
    final repository = FakeReturnRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [returnRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: ReturnScreen(
            organizationId: 'org',
            invoice: {
              'id': 'invoice',
              'invoice_number': 'INV/1',
              'items': [
                {
                  'id': 'line',
                  'qty': '3',
                  'returned_qty': '2',
                  'snapshot': {'name': 'Rice', 'type': 'product'},
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '2');
    await tester.enterText(find.byType(TextFormField).last, 'Damaged goods');
    await tester.ensureVisible(find.text('Review return'));
    await tester.tap(find.text('Review return'));
    await tester.pumpAndSettle();
    expect(repository.calls, 0);
    expect(find.text('Exceeds remaining quantity'), findsOneWidget);
  });
}
