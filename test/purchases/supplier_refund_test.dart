import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/purchases/presentation/supplier_refund_screen.dart';
import 'payment_test.dart' show FakePurchaseDetailRepository;

void main() {
  testWidgets(
    'supplier refund cannot exceed credit and requires confirmation',
    (tester) async {
      final repository = FakePurchaseDetailRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: SupplierRefundScreen(
            repository: repository,
            organizationId: 'org',
            purchaseId: 'purchase',
            creditDue: '42.27',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '42.28');
      await tester.tap(find.text('Record supplier refund'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an amount up to the supplier credit'),
        findsOneWidget,
      );
      expect(repository.supplierRefunds, 0);
      await tester.enterText(find.byType(TextFormField).first, '42.27');
      await tester.tap(find.text('Record supplier refund'));
      await tester.pumpAndSettle();
      expect(repository.supplierRefunds, 0);
      await tester.tap(find.text('Confirm refund'));
      await tester.pumpAndSettle();
      expect(repository.supplierRefunds, 1);
    },
  );
}
