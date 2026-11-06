import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/sales/domain/refund_repository.dart';
import 'package:smart_billing/features/sales/presentation/refund_form.dart';

class FakeRefundRepository implements RefundRepository {
  int calls = 0;
  @override
  Future<void> record(
    String key,
    String org,
    String invoice,
    String amount,
    String method,
    String reference,
    String reason,
  ) async {
    calls++;
  }
}

void main() {
  testWidgets('refund needs positive amount and reason before confirmation', (
    tester,
  ) async {
    final repository = FakeRefundRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [refundRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RefundForm(
                organizationId: 'org',
                invoiceId: 'invoice',
                onSaved: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.ensureVisible(find.text('Review refund'));
    await tester.tap(find.text('Review refund'));
    await tester.pumpAndSettle();
    expect(repository.calls, 0);
    expect(find.text('Enter a positive amount'), findsOneWidget);
    expect(find.text('Enter a reason (3+ characters)'), findsOneWidget);
  });
}
