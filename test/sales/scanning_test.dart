import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/sales/domain/draft_repository.dart';
import 'package:smart_billing/features/sales/presentation/drafts_screen.dart';
import 'package:smart_billing/integrations/scanning/barcode_scanner.dart';

class ScanSaleRepository implements DraftRepository {
  @override
  Future<List<SaleOption>> options(String org, String type) async =>
      type == 'products'
      ? [const SaleOption('rice', 'Rice', barcode: '00123', sku: 'RICE')]
      : type == 'customers'
      ? []
      : [const SaleOption('outlet', 'Shop')];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected write');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'known scan selects product without posting sale; unknown scan keeps cart',
    (tester) async {
      String code = '00123';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            saleActorIdProvider.overrideWithValue('actor'),
            draftRepositoryProvider.overrideWithValue(ScanSaleRepository()),
            barcodeScannerProvider.overrideWithValue((_) async => code),
          ],
          child: const MaterialApp(home: SaleEditor(organizationId: 'org')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scan product'));
      await tester.pumpAndSettle();
      expect(
        tester
            .stateList<FormFieldState<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .where((s) => s.value == 'rice'),
        hasLength(1),
      );
      code = 'UNKNOWN';
      await tester.tap(find.byTooltip('Scan product'));
      await tester.pumpAndSettle();
      expect(
        find.text('No active product matches this barcode.'),
        findsOneWidget,
      );
      expect(
        tester
            .stateList<FormFieldState<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .where((s) => s.value == 'rice'),
        hasLength(1),
      );
    },
  );
}
