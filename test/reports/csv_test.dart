import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/reports/domain/report_csv.dart';
import 'package:smart_billing/features/reports/domain/report_repository.dart';

void main() {
  test('stock valuation CSV retains rows without a recorded cost', () {
    final csv = ReportCsv.encodeStockValuation(
      FinancialReport({
        'total': 375,
        'uncosted_count': 1,
        'rows': [
          {
            'name': 'Demo rice',
            'quantity': 9,
            'estimate': 375,
            'unit_cost': 41.666667,
          },
          {'name': '=Opening stock', 'quantity': 2, 'estimate': null},
        ],
      }),
    );
    expect(csv, contains('375'));
    expect(csv, contains('"\'=Opening stock"'));
    expect(csv, contains('No positive recorded cost'));
  });
  test('CSV quotes text and neutralizes formula-like references', () {
    expect(ReportCsv.cell('A,"B"'), '"A,""B"""');
    expect(ReportCsv.cell('=HYPERLINK("bad")'), '"\'=HYPERLINK(""bad"")"');
    expect(ReportCsv.cell(-12.50), '"-12.5"');
    expect(ReportCsv.cell(' @SUM(1)'), '"\' @SUM(1)"');
  });
  test('CSV contains filters, generated timestamp and every snapshot row', () {
    final csv = ReportCsv.encode(
      FinancialReport({
        'kind': 'sales',
        'from': '2026-11-01',
        'to': '2026-11-05',
        'generated_at': '2026-11-05T10:00:00Z',
        'total': 55,
        'note': 'Posted records',
        'rows': List.generate(
          55,
          (i) => {
            'date': '2026-11-05',
            'type': 'invoice',
            'reference': 'INV-$i',
            'amount': 1,
          },
        ),
      }),
    );
    expect(csv, contains('2026-11-01'));
    expect(csv, contains('2026-11-05T10:00:00Z'));
    expect(csv, contains('INV-54'));
    expect(csv.split('INV-').length - 1, 55);
  });
}
