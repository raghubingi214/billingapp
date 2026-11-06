import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/sales/data/shared_preferences_pending_invoice_store.dart';
import 'package:smart_billing/features/sales/domain/pending_invoice_issue.dart';
import 'package:smart_billing/features/sales/domain/draft_repository.dart';

PendingInvoiceIssue _command(
  String key, {
  String org = 'org',
  String draft = 'draft',
}) => PendingInvoiceIssue(
  key,
  org,
  SaleDraft({'id': draft, 'version': 2, 'items': []}),
  {'grand_total': '100'},
  '2026-11-07',
  tenders: [
    {'method': 'upi', 'amount': '100', 'reference': 'PAY-001'},
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'invoice commands survive store recreation and retain split payment data',
    () async {
      final command = _command('request');
      await SharedPreferencesPendingInvoiceStore().save('actor', command);
      final reopened = SharedPreferencesPendingInvoiceStore();
      expect(
        (await reopened.list('actor', 'org')).single.toJson(),
        command.toJson(),
      );
      expect(await reopened.list('other', 'org'), isEmpty);
      expect(await reopened.list('actor', 'other-org'), isEmpty);
      await reopened.save('actor', _command('second', draft: 'second-draft'));
      await reopened.clear('actor', command);
      expect((await reopened.list('actor', 'org')).single.requestId, 'second');
    },
  );
  test(
    'another request cannot overwrite or clear an uncertain confirmation',
    () async {
      final store = SharedPreferencesPendingInvoiceStore();
      await store.save('actor', _command('original'));
      await expectLater(
        store.save('actor', _command('replacement')),
        throwsStateError,
      );
      await expectLater(
        store.clear('actor', _command('replacement')),
        throwsStateError,
      );
      expect((await store.list('actor', 'org')).single.requestId, 'original');
    },
  );
  test('missing identity cannot read or persist commands', () async {
    final store = SharedPreferencesPendingInvoiceStore();
    await expectLater(store.list('', 'org'), throwsStateError);
    await expectLater(store.save('', _command('request')), throwsStateError);
  });
}
