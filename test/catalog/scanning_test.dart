import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/catalog/presentation/catalog_screen.dart';
import 'package:smart_billing/integrations/scanning/barcode_scanner.dart';
import 'search_test.dart' show SearchRepository;

void main() {
  testWidgets('scan preserves leading zeroes and searches full catalog', (
    tester,
  ) async {
    final repository = SearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
          barcodeScannerProvider.overrideWithValue(
            (_) async => '0012345678905',
          ),
        ],
        child: const MaterialApp(
          home: CatalogScreen(organizationId: 'org', canManage: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Scan barcode'));
    await tester.pumpAndSettle();
    expect(repository.queries, ['', '0012345678905']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '0012345678905',
    );
  });
  testWidgets('cancelled scanner keeps current search', (tester) async {
    final repository = SearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogRepositoryProvider.overrideWithValue(repository),
          barcodeScannerProvider.overrideWithValue((_) async => null),
        ],
        child: const MaterialApp(
          home: CatalogScreen(organizationId: 'org', canManage: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tea');
    await tester.pumpAndSettle(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Scan barcode'));
    await tester.pumpAndSettle();
    expect(repository.queries, ['', 'Tea']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Tea',
    );
  });
}
