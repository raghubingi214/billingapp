import 'report_repository.dart';

class ReportCsv {
  static String encodeStockValuation(FinancialReport report) {
    final data = report.values;
    return _encodeRows([
      ['Report', 'Stock valuation'],
      ['As of', data['as_of']],
      ['Generated', data['generated_at']],
      ['Currency', 'INR'],
      ['Estimated value', data['total']],
      ['Positions without positive recorded cost', data['uncosted_count']],
      [
        'Basis',
        'Recorded average purchase cost. Opening stock, adjustments and returns can affect the estimate.',
      ],
      [],
      [
        'Product',
        'SKU',
        'Location',
        'On hand',
        'Unit',
        'Low stock',
        'Average cost',
        'Estimated value',
        'Cost status',
      ],
      for (final row in data['rows'] as List)
        [
          row['name'],
          row['sku'],
          row['outlet'],
          row['quantity'],
          row['unit'],
          row['low_stock'] == true ? 'Yes' : 'No',
          row['unit_cost'],
          row['estimate'],
          row['estimate'] == null ? 'No positive recorded cost' : 'Estimated',
        ],
    ]);
  }

  static String encodeAging(FinancialReport report) {
    final data = report.values;
    const amounts = [
      'current_due',
      'days_1_30',
      'days_31_60',
      'days_61_90',
      'days_91_plus',
      'total',
    ];
    final rows = <List<Object?>>[
      ['Report', 'Customer aging'],
      ['As of', data['as_of']],
      ['Generated', data['generated_at']],
      ['Currency', 'INR'],
      ['Basis', 'Open invoice balances after payments, returns and refunds'],
      [],
      [
        'Customer',
        'Current',
        '1–30 overdue',
        '31–60 overdue',
        '61–90 overdue',
        '91+ overdue',
        'Outstanding',
      ],
      ['All customers', for (final key in amounts) data[key]],
      for (final row in data['rows'] as List)
        [row['name'], for (final key in amounts) row[key]],
    ];
    return _encodeRows(rows);
  }

  static String encode(FinancialReport report) {
    final data = report.values;
    final columns = [
      'date',
      'type',
      'reference',
      'taxable',
      'tax',
      'method',
      'amount',
    ];
    final rows = <List<Object?>>[
      ['Report', data['kind']],
      ['From', data['from']],
      ['To', data['to']],
      ['Generated', data['generated_at']],
      ['Currency', 'INR'],
      ['Total', data['total']],
      ['Note', data['note']],
      [],
      columns,
      for (final row in data['rows'] as List)
        columns.map((key) => row[key]).toList(),
    ];
    return _encodeRows(rows);
  }

  static String _encodeRows(List<List<Object?>> rows) =>
      '${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';

  static String cell(Object? value) {
    var text = value?.toString() ?? '';
    if (value is! num && RegExp(r'^[\s]*[=+@-]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
