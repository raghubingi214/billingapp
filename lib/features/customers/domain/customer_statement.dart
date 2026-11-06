class CustomerStatement {
  const CustomerStatement(this.values);
  final Map<String, dynamic> values;
}

abstract interface class StatementExportRepository {
  Future<CustomerStatement> export(
    String requestId,
    String organizationId,
    String customerId,
    String from,
    String to,
  );
}

class StatementCsv {
  static String encode(CustomerStatement statement) {
    final data = statement.values;
    const columns = ['date', 'type', 'reference', 'debit', 'credit', 'balance'];
    final rows = <List<Object?>>[
      ['Statement', data['export_id']],
      ['Customer', data['customer_name']],
      ['From', data['from']],
      ['To', data['to']],
      ['Generated', data['generated_at']],
      ['Currency', 'INR'],
      ['Opening balance', data['opening_balance']],
      ['Closing balance', data['closing_balance']],
      ['Transactions', data['count']],
      [
        'Note',
        'Receipts include unapplied advances. Positive balance is receivable.',
      ],
      [],
      columns,
      for (final row in data['entries'] as List)
        columns.map((key) => row[key]).toList(),
    ];
    return '${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n';
  }

  static String _cell(Object? value) {
    var text = value?.toString() ?? '';
    if (value is! num && RegExp(r'^[\s]*[=+@-]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
