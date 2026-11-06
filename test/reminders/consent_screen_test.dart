import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/reminders/domain/reminder_consent_repository.dart';
import 'package:smart_billing/features/reminders/presentation/reminder_consent_screen.dart';

class _Repository implements ReminderConsentRepository {
  bool failLoad = false;
  List<Map<String, dynamic>> rows = [];
  final commands = <String>[];
  @override
  Future<List<Map<String, dynamic>>> load(
    String organizationId,
    String customerId,
  ) async {
    if (failLoad) throw StateError('Offline');
    return rows;
  }

  @override
  Future<void> save(
    String requestId,
    String organizationId,
    String customerId,
    String channel,
    bool allowed,
    String evidence,
    int version,
  ) async {
    commands.add(
      '$requestId:$organizationId:$customerId:$channel:$allowed:$evidence:$version',
    );
    throw StateError('Response lost');
  }
}

void main() {
  testWidgets('changed contact does not display old permission as enabled', (
    tester,
  ) async {
    final repository = _Repository()
      ..rows = [
        {
          'channel': 'email',
          'allowed': true,
          'version': 1,
          'recipient': 'old@example.invalid',
          'current_recipient': 'new@example.invalid',
        },
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reminderConsentRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: ReminderConsentScreen(
            organizationId: 'org-a',
            customerId: 'customer-a',
            customerName: 'Customer',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.textContaining('Contact details changed'), findsOneWidget);
    expect(repository.commands, isEmpty);
  });
  Widget app(_Repository repository) => ProviderScope(
    overrides: [
      reminderConsentRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      home: ReminderConsentScreen(
        organizationId: 'org-a',
        customerId: 'customer-a',
        customerName: 'Customer',
      ),
    ),
  );
  testWidgets('missing evidence blocks writes and default is denied', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('Save consent'));
    await tester.pumpAndSettle();
    expect(repository.commands, isEmpty);
    expect(find.textContaining('Record consent evidence'), findsOneWidget);
  });
  testWidgets('failed response retries identical command', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Customer opted out');
    await tester.tap(find.text('Save consent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save consent'));
    await tester.pumpAndSettle();
    expect(repository.commands.length, 2);
    expect(repository.commands.first, repository.commands.last);
  });
  testWidgets('load failure disables all consent editing', (tester) async {
    await tester.pumpWidget(app(_Repository()..failLoad = true));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });
}
