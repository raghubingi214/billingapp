import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/sales/domain/receipt_repository.dart';
import 'package:smart_billing/features/sales/presentation/receipt_form.dart';

class FakeReceiptRepository implements ReceiptRepository {
  int calls = 0;
  @override
  Future<void> record(
    String key,
    String org,
    String customer,
    String invoice,
    String amount,
    String method,
    String reference,
    String date,
  ) async {
    calls++;
  }
}

void main() {
  testWidgets('invalid receipt precision never reaches backend', (
    tester,
  ) async {
    final repository = FakeReceiptRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [receiptRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceiptForm(
                organizationId: 'org',
                customerId: 'customer',
                invoiceId: 'invoice',
                onSaved: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '1.001');
    await tester.tap(find.text('Record receipt'));
    await tester.pumpAndSettle();
    expect(repository.calls, 0);
    expect(find.text('Enter a positive amount'), findsOneWidget);
  });
}
