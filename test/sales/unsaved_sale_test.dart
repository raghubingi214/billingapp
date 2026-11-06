import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/sales/domain/draft_repository.dart';
import 'package:smart_billing/features/sales/presentation/drafts_screen.dart';
import 'package:smart_billing/features/sales/domain/pending_invoice_issue.dart';
import 'package:smart_billing/features/sales/data/shared_preferences_pending_invoice_store.dart';

const _draft = SaleDraft({
  'id': 'draft',
  'version': 1,
  'outlet_id': 'outlet',
  'customer_id': 'customer',
  'place_of_supply': '36',
  'notes': '',
  'items': [
    {
      'product_id': 'product',
      'qty': '1',
      'discount_kind': 'fixed',
      'discount': '0',
    },
  ],
});

class _Drafts implements DraftRepository {
  int saves = 0, issues = 0;
  bool failIssue = false;
  bool rejectIssue = false;
  final issueKeys = <String>[];
  @override
  Future<List<SaleDraft>> drafts(String organizationId, int offset) async => [];
  @override
  Future<List<SaleOption>> options(String org, String type) async => [
    SaleOption(switch (type) {
      'outlets' => 'outlet',
      'customers' => 'customer',
      _ => 'product',
    }, type),
  ];
  @override
  Future<SaleDraft> save(
    String requestId,
    String organizationId,
    SaleDraft? previous,
    String outletId,
    String? customerId,
    String state,
    List<Map<String, String>> items,
    String notes,
  ) async {
    saves++;
    return SaleDraft({
      ..._draft.values,
      'version': saves + 1,
      'outlet_id': outletId,
      'customer_id': customerId,
      'place_of_supply': state,
      'notes': notes,
      'items': items,
    });
  }

  @override
  Future<Map<String, dynamic>> quote(
    String organizationId,
    SaleDraft draft,
  ) async => {'taxable_total': '100', 'tax_total': '0', 'grand_total': '100'};
  @override
  Future<void> issue(
    String requestId,
    String organizationId,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String dueDate,
  ) async {
    issues++;
    issueKeys.add(requestId);
    if (rejectIssue) throw const InvoiceIssueRejected('INSUFFICIENT_STOCK');
    if (failIssue) throw StateError('Response lost');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected command');
}

class _UnavailableStore implements PendingInvoiceStore {
  int saves = 0;
  @override
  Future<List<PendingInvoiceIssue>> list(
    String actorId,
    String organizationId,
  ) async => [];
  @override
  Future<void> save(String actorId, PendingInvoiceIssue command) async {
    saves++;
    throw StateError('Storage unavailable');
  }

  @override
  Future<void> clear(String actorId, PendingInvoiceIssue command) async =>
      throw StateError('Unexpected clear');
}

class _DelayedStore extends _UnavailableStore {
  final saved = Completer<void>();
  @override
  Future<void> save(String actorId, PendingInvoiceIssue command) {
    saves++;
    return saved.future;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Drafts repository, {
  PendingInvoiceStore? store,
  String Function()? currentActor,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        saleActorIdProvider.overrideWith(
          (ref) => currentActor?.call() ?? 'actor',
        ),
        if (store != null) pendingInvoiceStoreProvider.overrideWithValue(store),
        draftRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const SaleEditor(organizationId: 'org', draft: _draft),
                ),
              ),
              child: const Text('Open sale'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sale'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    500,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('impossible due date cannot save a draft or issue a sale', (
    tester,
  ) async {
    final repository = _Drafts();
    await _open(tester, repository);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Due date (YYYY-MM-DD)'),
      '2026-02-30',
    );
    await _tap(tester, 'Save draft');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tap(tester, 'Review and issue');
    expect(repository.saves, 0);
    expect(repository.issues, 0);
  });
  testWidgets(
    'definite stock rejection clears pending command and permits corrections',
    (tester) async {
      final repository = _Drafts()..rejectIssue = true;
      await _open(tester, repository);
      await _tap(tester, 'Review and issue');
      await tester.tap(find.text('Issue invoice').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Invoice was not issued. Adjust quantities or check stock before retrying.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry pending invoice'), findsNothing);
      expect(find.text('Review and issue'), findsOneWidget);
      expect(
        await SharedPreferencesPendingInvoiceStore().list('actor', 'org'),
        isEmpty,
      );
    },
  );
  testWidgets('session change during local save prevents sending an invoice', (
    tester,
  ) async {
    var actor = 'actor';
    final store = _DelayedStore();
    final repository = _Drafts();
    await _open(tester, repository, store: store, currentActor: () => actor);
    await _tap(tester, 'Review and issue');
    await tester.tap(find.text('Issue invoice').last);
    await tester.pumpAndSettle();
    expect(store.saves, 1);
    actor = 'other';
    ProviderScope.containerOf(
      tester.element(find.byType(SaleEditor)),
      listen: false,
    ).invalidate(saleActorIdProvider);
    store.saved.complete();
    await tester.pumpAndSettle();
    expect(repository.issues, 0);
  });
  testWidgets(
    'reopened draft list recovers an uncertain invoice even when server has no active drafts',
    (tester) async {
      final repository = _Drafts()..failIssue = true;
      await _open(tester, repository);
      await _tap(tester, 'Review and issue');
      await tester.tap(find.text('Issue invoice').last);
      await tester.pumpAndSettle();
      final store = SharedPreferencesPendingInvoiceStore();
      final saved = (await store.list('actor', 'org')).single;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            saleActorIdProvider.overrideWithValue('actor'),
            draftRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: DraftsScreen(organizationId: 'org')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invoice confirmation pending'));
      await tester.pumpAndSettle();
      repository.failIssue = false;
      await _tap(tester, 'Retry pending invoice');
      expect(repository.issueKeys, [saved.requestId, saved.requestId]);
      expect(repository.saves, 1);
      expect(await store.list('actor', 'org'), isEmpty);
      expect(find.text('No saved drafts'), findsOneWidget);
    },
  );
  testWidgets('failed local command save prevents invoice issue', (
    tester,
  ) async {
    final repository = _Drafts();
    final store = _UnavailableStore();
    await _open(tester, repository, store: store);
    await _tap(tester, 'Review and issue');
    await tester.tap(find.text('Issue invoice').last);
    await tester.pumpAndSettle();
    expect(store.saves, 1);
    expect(repository.issues, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This confirmation could not be saved on this device. Keep this screen open and retry before leaving.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('unchanged saved sale leaves without a warning', (tester) async {
    await _open(tester, _Drafts());
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open sale'), findsOneWidget);
    expect(find.text('Discard unsaved changes?'), findsNothing);
  });
  testWidgets(
    'Android Back offers keep editing or discard without sending changes',
    (tester) async {
      final repository = _Drafts();
      await _open(tester, repository);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Place of supply state code'),
        '37',
      );
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('37'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Open sale'), findsOneWidget);
      expect(repository.saves, 0);
      expect(repository.issues, 0);
    },
  );
  testWidgets('confirmed draft save clears draft-field warning', (
    tester,
  ) async {
    final repository = _Drafts();
    await _open(tester, repository);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Place of supply state code'),
      '37',
    );
    await _tap(tester, 'Save draft');
    expect(repository.saves, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open sale'), findsOneWidget);
  });
  testWidgets('due date remains unsaved after saving a draft', (tester) async {
    final repository = _Drafts();
    await _open(tester, repository);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Due date (YYYY-MM-DD)'),
      '2099-01-01',
    );
    await _tap(tester, 'Save draft');
    expect(repository.saves, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
  });
  testWidgets(
    'uncertain issue warns before exit and confirmed issue exits directly',
    (tester) async {
      final repository = _Drafts()..failIssue = true;
      await _open(tester, repository);
      await _tap(tester, 'Review and issue');
      await tester.tap(find.text('Issue invoice').last);
      await tester.pumpAndSettle();
      expect(repository.issues, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Invoice confirmation pending'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      repository.failIssue = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _tap(tester, 'Retry pending invoice');
      expect(repository.issues, 2);
      expect(find.text('Open sale'), findsOneWidget);
    },
  );
}
