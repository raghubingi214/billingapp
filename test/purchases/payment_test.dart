import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/purchases/domain/purchase_detail_repository.dart';
import 'package:smart_billing/features/purchases/presentation/purchase_detail_screen.dart';

class FakePurchaseDetailRepository implements PurchaseDetailRepository {
  int payments = 0;
  int supplierRefunds = 0;
  @override
  Future<void> recordSupplierCreditRefund(
    String requestId,
    String organizationId,
    String purchaseId,
    String amount,
    String date,
    String method,
    String? reference,
  ) async {
    supplierRefunds++;
  }

  @override
  Future<Map<String, dynamic>> previewReturn(
    String organizationId,
    String purchaseId,
    List<Map<String, String>> items,
  ) async => {'total': '42.26', 'lines': items};
  @override
  Future<void> returnPurchase(
    String requestId,
    String organizationId,
    String purchaseId,
    String reason,
    String? reference,
    List<Map<String, String>> items,
  ) async {}
  @override
  Future<PurchaseDetail> detail(
    String organizationId,
    String purchaseId,
  ) async => const PurchaseDetail({
    'supplier_id': 'supplier',
    'supplier_snapshot': {'name': 'Vendor'},
    'supplier_bill_no': 'BILL-1',
    'bill_date': '2026-11-05',
    'grand_total': '500.00',
    'paid_total': '100.00',
    'balance_due': '400.00',
    'items': [],
    'payments': [],
  });
  @override
  Future<void> pay(
    String requestId,
    String organizationId,
    String supplierId,
    String purchaseId,
    String amount,
    String method,
    String reference,
    String date,
  ) async {
    payments++;
  }
}

class ReturnPurchaseRepository extends FakePurchaseDetailRepository {
  int previews = 0, returns = 0;
  @override
  Future<PurchaseDetail> detail(
    String organizationId,
    String purchaseId,
  ) async => const PurchaseDetail({
    'supplier_id': 'supplier',
    'supplier_snapshot': {'name': 'Vendor'},
    'supplier_bill_no': 'BILL-1',
    'bill_date': '2026-11-05',
    'grand_total': '422.63',
    'paid_total': '0',
    'balance_due': '422.63',
    'items': [
      {
        'id': 'item',
        'qty': '10',
        'unit_cost': '40.25',
        'tax_percent': '5',
        'line_total': '422.63',
        'product_snapshot': {'name': 'Rice'},
      },
    ],
    'payments': [],
  });
  @override
  Future<Map<String, dynamic>> previewReturn(
    String organizationId,
    String purchaseId,
    List<Map<String, String>> items,
  ) async {
    previews++;
    expect(items.single, {'purchase_item_id': 'item', 'qty': '1'});
    return {'total': '42.26', 'lines': items};
  }

  @override
  Future<void> returnPurchase(
    String requestId,
    String organizationId,
    String purchaseId,
    String reason,
    String? reference,
    List<Map<String, String>> items,
  ) async {
    returns++;
  }
}

class ReturnedPurchaseRepository extends ReturnPurchaseRepository {
  @override
  Future<PurchaseDetail> detail(
    String organizationId,
    String purchaseId,
  ) async {
    final original = await super.detail(organizationId, purchaseId);
    return PurchaseDetail({
      ...original.values,
      'paid_total': '100.00',
      'returned_total': '42.26',
      'net_payable': '380.37',
      'balance_due': '280.37',
      'supplier_credit_due': '0.00',
      'items': [
        {
          ...(original.values['items'] as List).single as Map<String, dynamic>,
          'returned_qty': '1',
        },
      ],
      'returns': [
        {'total': '42.26', 'date': '2026-11-05', 'reason': 'Damaged goods'},
      ],
    });
  }
}

class LostReturnResponseRepository extends ReturnPurchaseRepository {
  final keys = <String>[];
  @override
  Future<void> returnPurchase(
    String requestId,
    String organizationId,
    String purchaseId,
    String reason,
    String? reference,
    List<Map<String, String>> items,
  ) async {
    keys.add(requestId);
    expect(items.single, {'purchase_item_id': 'item', 'qty': '1'});
    if (keys.length == 1) throw Exception('Response lost after commit');
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    FakePurchaseDetailRepository repository, {
    bool canPay = true,
    String? actor,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          purchaseDetailRepositoryProvider.overrideWithValue(repository),
          if (actor != null)
            purchaseReturnActorIdProvider.overrideWithValue(actor),
        ],
        child: MaterialApp(
          home: PurchaseDetailScreen(
            organizationId: 'org',
            purchaseId: 'purchase',
            canPay: canPay,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'read-only purchase view shows server balance without payment form',
    (tester) async {
      final repository = FakePurchaseDetailRepository();
      await open(tester, repository, canPay: false);
      expect(find.text('Balance due ₹400.00'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    },
  );
  testWidgets('invalid payment amount never reaches repository', (
    tester,
  ) async {
    final repository = FakePurchaseDetailRepository();
    await open(tester, repository);
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.ensureVisible(find.text('Record payment'));
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(repository.payments, 0);
    expect(find.text('Enter an amount up to the balance due'), findsOneWidget);
  });
  testWidgets(
    'return checks quantity and asks for server credit confirmation',
    (tester) async {
      final repository = ReturnPurchaseRepository();
      await open(tester, repository);
      await tester.ensureVisible(find.text('Return goods to supplier'));
      await tester.tap(find.text('Return goods to supplier'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            )
            .at(0),
        '11',
      );
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            )
            .at(1),
        'Damaged goods',
      );
      await tester.tap(find.text('Preview credit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter up to the remaining quantity'), findsOneWidget);
      expect(repository.previews, 0);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            )
            .at(0),
        '1',
      );
      await tester.tap(find.text('Preview credit'));
      await tester.pumpAndSettle();
      expect(repository.previews, 1);
      expect(repository.returns, 0);
      expect(find.textContaining('Credit ₹42.26'), findsOneWidget);
      await tester.tap(find.text('Post return'));
      await tester.pumpAndSettle();
      expect(repository.returns, 1);
    },
  );
  testWidgets('returned goods reduce payable and returnable quantity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = ReturnedPurchaseRepository();
    await open(tester, repository);
    expect(find.text('Returned credit ₹42.26'), findsOneWidget);
    expect(find.text('Net payable ₹380.37'), findsOneWidget);
    expect(find.text('Balance due ₹280.37'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '280.38');
    await tester.ensureVisible(find.text('Record payment'));
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount up to the balance due'), findsOneWidget);
    expect(repository.payments, 0);
    await tester.ensureVisible(find.text('Return goods to supplier'));
    await tester.tap(find.text('Return goods to supplier'));
    await tester.pumpAndSettle();
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.at(0), '10');
    await tester.enterText(dialogFields.at(1), 'Damaged goods');
    await tester.tap(find.text('Preview credit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter up to the remaining quantity'), findsOneWidget);
    expect(repository.previews, 0);
  });
  testWidgets(
    'lost return response retries identical command without a second preview',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = LostReturnResponseRepository();
      await open(tester, repository, actor: 'owner-actor');
      await tester.ensureVisible(find.text('Return goods to supplier'));
      await tester.tap(find.text('Return goods to supplier'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(fields.at(0), '1');
      await tester.enterText(fields.at(1), 'Damaged goods');
      await tester.tap(find.text('Preview credit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post return'));
      await tester.pumpAndSettle();
      expect(repository.previews, 1);
      expect(find.text('Retry pending return'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await open(tester, repository, actor: 'other-actor');
      expect(find.text('Retry pending return'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await open(tester, repository, actor: 'owner-actor');
      expect(find.text('Retry pending return'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry pending return'));
      await tester.tap(find.text('Retry pending return'));
      await tester.pumpAndSettle();
      expect(repository.keys, hasLength(2));
      expect(repository.keys[0], repository.keys[1]);
      expect(repository.previews, 1);
      expect(find.text('Retry pending return'), findsNothing);
    },
  );
}
