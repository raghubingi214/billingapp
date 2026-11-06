import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/sales/domain/draft_repository.dart';
import 'package:smart_billing/features/sales/domain/pending_invoice_issue.dart';

class RetryRepository implements DraftRepository {
  final calls = <String>[];
  @override
  Future<void> checkout(
    String key,
    String org,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String due,
    List<Map<String, String>> tenders,
  ) async {
    calls.add('checkout:$key|$org|${draft.values}|$quote|$due|$tenders');
    if (calls.length == 1) throw StateError('Response lost');
  }

  @override
  Future<void> issue(
    String key,
    String org,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String due,
  ) async {
    calls.add('$key|$org|${draft.values}|$quote|$due');
    if (calls.length == 1) throw StateError('Response lost');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected command');
}

void main() {
  test(
    'split checkout retry preserves tender references and amounts',
    () async {
      final repository = RetryRepository();
      final tenders = [
        {'amount': '25.00', 'method': 'upi', 'reference': 'REF-1'},
        {'amount': '75.00', 'method': 'cash', 'reference': ''},
      ];
      final pending = PendingInvoiceIssue(
        'checkout-key',
        'org',
        const SaleDraft({'id': 'draft', 'version': 1}),
        {'grand_total': '100.00'},
        '2026-11-05',
        tenders: tenders,
      );
      await expectLater(pending.send(repository), throwsStateError);
      tenders.first['amount'] = '99.00';
      tenders.last['method'] = 'bank';
      await pending.send(repository);
      expect(repository.calls[0], repository.calls[1]);
      expect(repository.calls[1], contains('REF-1'));
    },
  );
  test(
    'lost issue response retries exact confirmed input without saving draft',
    () async {
      final repository = RetryRepository();
      final draftValues = <String, dynamic>{'id': 'draft', 'version': 3};
      final quote = <String, dynamic>{
        'grand_total': '100.00',
        'items': [
          {'qty': '1'},
        ],
      };
      final pending = PendingInvoiceIssue(
        'same-key',
        'org',
        SaleDraft(draftValues),
        quote,
        '2026-11-05',
      );
      await expectLater(pending.send(repository), throwsStateError);
      draftValues['version'] = 4;
      (quote['items'] as List).clear();
      await pending.send(repository);
      expect(repository.calls.length, 2);
      expect(repository.calls[0], repository.calls[1]);
    },
  );
}
