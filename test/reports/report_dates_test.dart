import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/reports/domain/report_repository.dart';
import 'package:smart_billing/features/reports/presentation/reports_screen.dart';
import 'package:smart_billing/features/reports/presentation/customer_aging_screen.dart';
import 'package:smart_billing/features/reports/presentation/stock_valuation_screen.dart';
import 'package:smart_billing/features/reports/presentation/report_snapshot_export_button.dart';

class _Reports implements ReportRepository {
  @override
  Future<FinancialReport> exportStockValuation(
    String requestId,
    String organizationId,
  ) async {
    final page = await stockValuation(organizationId, 0);
    return FinancialReport({...page.values, 'as_of': '2026-11-07'});
  }

  int loads = 0, exports = 0;
  @override
  Future<FinancialReport> stockValuation(
    String organizationId,
    int offset,
  ) async {
    expect(organizationId, 'demo');
    expect(offset, 0);
    return const FinancialReport({
      'count': 2,
      'uncosted_count': 1,
      'low_stock_count': 1,
      'total': 375,
      'rows': [
        {
          'name': 'Demo Rice',
          'outlet': 'Main',
          'quantity': 9,
          'unit': 'kg',
          'low_stock': true,
          'unit_cost': 41.666667,
          'estimate': 375,
        },
        {
          'name': 'Uncosted opening stock',
          'outlet': 'Main',
          'quantity': 2,
          'unit': 'kg',
          'low_stock': false,
          'unit_cost': null,
          'estimate': null,
        },
      ],
    });
  }

  final agingExportIds = <String>[];
  @override
  Future<FinancialReport> exportCustomerAging(
    String requestId,
    String organizationId,
  ) async {
    agingExportIds.add(requestId);
    final page = await customerAging(organizationId, 0);
    return FinancialReport({
      ...page.values,
      'generated_at': '2026-11-07T10:00:00Z',
      'rows': List.generate(55, (index) => {'name': '=Customer ${index + 1}'}),
    });
  }

  @override
  Future<FinancialReport> customerAging(
    String organizationId,
    int offset,
  ) async {
    expect(organizationId, 'demo');
    expect(offset, 0);
    const amounts = {
      'current_due': 0,
      'days_1_30': 120,
      'days_31_60': 0,
      'days_61_90': 0,
      'days_91_plus': 0,
      'total': 120,
    };
    return const FinancialReport({
      ...amounts,
      'as_of': '2026-11-07',
      'count': 1,
      'rows': [
        {...amounts, 'name': 'Demo Customer', 'customer_id': 'customer'},
      ],
    });
  }

  @override
  Future<FinancialReport> page(
    String org,
    String kind,
    String from,
    String to,
    int offset,
  ) async {
    loads++;
    return FinancialReport({
      'rows': [],
      'total': 0,
      'count': 0,
      'from': from,
      'to': to,
      'note': 'Posted records',
      'generated_at': '2026-11-06',
    });
  }

  @override
  Future<FinancialReport> export(
    String requestId,
    String org,
    String kind,
    String from,
    String to,
  ) async {
    exports++;
    throw StateError('Unexpected export');
  }
}

void main() {
  testWidgets('stock valuation flags uncosted stock separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reportRepositoryProvider.overrideWithValue(_Reports())],
        child: const MaterialApp(
          home: StockValuationScreen(organizationId: 'demo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Estimated stock value ₹375'), findsOneWidget);
    expect(
      find.text('1 positions without a positive recorded cost'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Uncosted opening stock'), 200);
    expect(find.textContaining('No positive recorded cost'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('aging exports every snapshot row and retries the same request', (
    tester,
  ) async {
    final reports = _Reports();
    String? shared;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportRepositoryProvider.overrideWithValue(reports),
          reportSnapshotShareProvider.overrideWithValue((
            csv,
            filename,
            origin,
          ) async {
            expect(filename, 'customer-aging-2026-11-07.csv');
            if (reports.agingExportIds.length == 1) {
              throw StateError('Share failed');
            }
            shared = csv;
          }),
        ],
        child: const MaterialApp(
          home: CustomerAgingScreen(organizationId: 'demo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Export full CSV'));
      await tester.pumpAndSettle();
    }
    expect(reports.agingExportIds.length, 2);
    expect(reports.agingExportIds.toSet(), hasLength(1));
    expect(shared, contains('"\'=Customer 55"'));
    expect(shared, contains('2026-11-07T10:00:00Z'));
  });
  testWidgets('customer aging displays the overdue bucket and customer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reportRepositoryProvider.overrideWithValue(_Reports())],
        child: const MaterialApp(
          home: CustomerAgingScreen(organizationId: 'demo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Outstanding ₹120'), findsWidgets);
    expect(find.text('1–30 days overdue'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Demo Customer'), 200);
    expect(find.text('Demo Customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'invalid dates and ranges block both report queries and exports',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Reports();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [reportRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: ReportsScreen(organizationId: 'org')),
        ),
      );
      await tester.pumpAndSettle();
      for (final dates in [
        ('2026-02-30', '2026-11-01'),
        ('2026-03-10', '2026-03-01'),
        ('2000-01-01', '2026-01-01'),
        ('0000-01-01', '2026-01-01'),
      ]) {
        await tester.enterText(find.byType(TextFormField).first, dates.$1);
        await tester.enterText(find.byType(TextFormField).last, dates.$2);
        await tester.pump();
        await tester.tap(find.text('Apply filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export full CSV'));
        await tester.pumpAndSettle();
      }
      expect(repository.loads, 1);
      expect(repository.exports, 0);
      await tester.enterText(find.byType(TextFormField).first, '2024-02-29');
      await tester.enterText(find.byType(TextFormField).last, '2024-03-01');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(repository.loads, 2);
    },
  );
}
