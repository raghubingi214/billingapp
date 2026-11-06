import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/customers/domain/ledger_repository.dart';
import 'package:smart_billing/features/customers/presentation/customer_ledger_screen.dart';
import 'package:smart_billing/features/customers/domain/customer_statement.dart';

class _Export implements StatementExportRepository {
  bool fail = true;
  final keys = <String>[];
  @override
  Future<CustomerStatement> export(
    String requestId,
    String organizationId,
    String customerId,
    String from,
    String to,
  ) async {
    keys.add(requestId);
    if (fail) throw StateError('Response lost');
    return CustomerStatement({
      'export_id': 'snapshot-1',
      'customer_name': '=SUM(1,2)',
      'from': from,
      'to': to,
      'generated_at': '2026-11-06',
      'opening_balance': 0,
      'closing_balance': 72,
      'count': 72,
      'entries': [
        for (var i = 0; i < 72; i++)
          {
            'date': from,
            'type': 'invoice',
            'reference': 'REF-$i',
            'debit': 1,
            'credit': 0,
            'balance': i + 1,
          },
      ],
    });
  }
}

class _Ledger implements LedgerRepository {
  bool fail = false;
  final calls = <({String from, String to, int offset})>[];
  @override
  Future<CustomerLedger> page(
    String organizationId,
    String customerId,
    String from,
    String to,
    int offset,
  ) async {
    calls.add((from: from, to: to, offset: offset));
    if (fail) throw StateError('Connection lost');
    return CustomerLedger({
      'customer_name': 'Customer A',
      'opening_balance': '0',
      'closing_balance': '50',
      'entries': [
        for (var i = 0; i < 50; i++)
          {
            'type': 'invoice',
            'reference': 'INV-${offset + i}',
            'date': from,
            'debit': '1',
            'credit': '0',
            'balance': '${offset + i + 1}',
          },
      ],
    });
  }
}

Future<void> _open(
  WidgetTester tester,
  _Ledger ledger, {
  StatementExportRepository? exporter,
  Future<void> Function(String, String, Rect)? share,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ledgerRepositoryProvider.overrideWithValue(ledger),
        if (exporter != null)
          statementExportRepositoryProvider.overrideWithValue(exporter),
        if (share != null) statementShareProvider.overrideWithValue(share),
      ],
      child: const MaterialApp(
        home: CustomerLedgerScreen(
          organizationId: 'org',
          customerId: 'customer',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'full statement retries lost response and reuses snapshot after share failure',
    (tester) async {
      final exporter = _Export();
      final shared = <String>[];
      var failShare = true;
      await _open(
        tester,
        _Ledger(),
        exporter: exporter,
        share: (csv, filename, origin) async {
          shared.add(csv);
          expect(filename, startsWith('customer-statement-'));
          expect(origin.width, greaterThan(0));
          if (failShare) throw StateError('Share unavailable');
        },
      );
      Future<void> export() async {
        await tester.ensureVisible(find.text('Share full statement CSV'));
        await tester.tap(find.text('Share full statement CSV'));
        await tester.pumpAndSettle();
      }

      await export();
      expect(shared, isEmpty);
      exporter.fail = false;
      await export();
      expect(exporter.keys[0], exporter.keys[1]);
      failShare = false;
      await export();
      expect(exporter.keys.length, 2);
      expect(shared[0], shared[1]);
      expect(shared.last, contains('REF-71'));
      expect(shared.last, contains("\"'=SUM(1,2)\""));
      await export();
      expect(exporter.keys.last, isNot(exporter.keys.first));
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '2026-02-30');
      await export();
      expect(exporter.keys.length, 3);
    },
  );
  testWidgets('edited dates clear old balances and restart paging at zero', (
    tester,
  ) async {
    final ledger = _Ledger();
    await _open(tester, ledger);
    expect(find.text('Customer A'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '2026-01-01');
    await tester.pump();
    expect(find.text('Customer A'), findsNothing);
    expect(find.text('Load more'), findsNothing);
    await tester.tap(find.text('Apply dates'));
    await tester.pumpAndSettle();
    expect(ledger.calls.last.from, '2026-01-01');
    expect(ledger.calls.last.offset, 0);
  });

  testWidgets('invalid calendar dates and reversed ranges never request data', (
    tester,
  ) async {
    final ledger = _Ledger();
    await _open(tester, ledger);
    for (final date in ['2026-02-30', '2026-1-01', '2099-12-31']) {
      await tester.enterText(find.byType(TextFormField).first, date);
      await tester.tap(find.text('Apply dates'));
      await tester.pumpAndSettle();
    }
    expect(ledger.calls.length, 1);
  });

  testWidgets('failed next page retries the same offset without losing rows', (
    tester,
  ) async {
    final ledger = _Ledger();
    await _open(tester, ledger);
    await tester.scrollUntilVisible(
      find.text('Load more'),
      600,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    ledger.fail = true;
    await tester.ensureVisible(find.text('Load more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(ledger.calls.last.offset, 50);
    ledger.fail = false;
    await tester.scrollUntilVisible(
      find.text('Load more'),
      600,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(ledger.calls.map((call) => call.offset), [0, 50, 50]);
    await tester.scrollUntilVisible(
      find.text('invoice · INV-50'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('invoice · INV-50'), findsOneWidget);
  });
}
