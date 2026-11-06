import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/reports/domain/report_repository.dart';
import 'package:smart_billing/features/reports/presentation/reports_screen.dart';

class _Reports implements ReportRepository {
  int loads = 0, exports = 0;
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
