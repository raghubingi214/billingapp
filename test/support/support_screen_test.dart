import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/support/domain/support_repository.dart';
import 'package:smart_billing/features/support/presentation/support_screen.dart';
import 'package:smart_billing/features/support/data/shared_preferences_pending_support_store.dart';
import 'package:smart_billing/features/support/presentation/support_thread_screen.dart';

class _Repository implements SupportRepository {
  final replyScopes = <String>[];
  List<Map<String, dynamic>> replyRows = [];
  @override
  Future<List<Map<String, dynamic>>> replies(
    String organizationId,
    String supportId,
    int offset,
  ) async {
    replyScopes.add('$organizationId:$supportId:$offset');
    return replyRows;
  }

  int calls = 0;
  bool fail = false;
  final keys = <String>[];
  @override
  Future<List<Map<String, dynamic>>> history(
    String organizationId,
    int offset,
  ) async => [];
  @override
  Future<void> submit(
    String requestId,
    String organizationId,
    String kind,
    String subject,
    String message,
  ) async {
    calls++;
    keys.add(requestId);
    if (fail) throw StateError('Response lost');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('thread reads only selected business and request and refreshes', (
    tester,
  ) async {
    final repository = _Repository()
      ..replyRows = [
        {
          'id': 'reply-a',
          'body': 'Your request is being reviewed.',
          'created_at': '2026-11-05T12:00:00Z',
        },
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: SupportThreadScreen(
            organizationId: 'business-a',
            supportId: 'request-a',
            subject: 'Export request',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your request is being reviewed.'), findsOneWidget);
    expect(repository.replyScopes, ['business-a:request-a:0']);
    repository.replyRows = [];
    await tester.tap(find.byTooltip('Refresh responses'));
    await tester.pumpAndSettle();
    expect(find.text('Your request is being reviewed.'), findsNothing);
    expect(find.text('No responses on this page yet.'), findsOneWidget);
    expect(repository.replyScopes.length, 2);
  });
  testWidgets(
    'reopened screen restores command and clears it after successful retry',
    (tester) async {
      final repository = _Repository()..fail = true;
      Widget app() => ProviderScope(
        overrides: [supportRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: SupportScreen(
            key: UniqueKey(),
            actorId: 'actor-a',
            organizationId: 'business-a',
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Help with records',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Please help with my business records.',
      );
      await tester.ensureVisible(find.text('Submit request'));
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      final firstKey = repository.keys.single;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      repository.fail = false;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Help with records'), findsOneWidget);
      expect(
        find.text('Please help with my business records.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Submit request'));
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(repository.keys, [firstKey, firstKey]);
      expect(
        await SharedPreferencesPendingSupportStore().load(
          'actor-a',
          'business-a',
        ),
        isNull,
      );
    },
  );
  testWidgets('lost response retries the same request key', (tester) async {
    final repository = _Repository()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: SupportScreen(actorId: 'actor-a', organizationId: 'business-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Export help');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Please help me export my business records.',
    );
    await tester.ensureVisible(find.text('Submit request'));
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    repository.fail = false;
    await tester.ensureVisible(find.text('Submit request'));
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(repository.keys.length, 2);
    expect(repository.keys[0], repository.keys[1]);
    expect(
      find.text('Request recorded. You can follow its status below.'),
      findsOneWidget,
    );
  });
  testWidgets('invalid support request never reaches repository', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supportRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: SupportScreen(actorId: 'actor-a', organizationId: 'business-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit request'));
    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least 3 characters'), findsOneWidget);
    expect(repository.calls, 0);
  });
}
