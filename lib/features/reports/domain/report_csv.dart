import 'report_repository.dart';

class ReportCsv {
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
    return '${rows.map((row) => row.map(cell).join(',')).join('\r\n')}\r\n';
  }

  static String cell(Object? value) {
    var text = value?.toString() ?? '';
    if (value is! num && RegExp(r'^[\s]*[=+@-]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
