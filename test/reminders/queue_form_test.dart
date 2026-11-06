import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/reminders/domain/reminder_queue_repository.dart';
import 'package:smart_billing/features/reminders/presentation/reminder_history_screen.dart';
import 'package:smart_billing/features/reminders/presentation/queue_reminder_form.dart';

class _Queue implements ReminderQueueRepository {
  ReminderQueueFailure? rejection;
  final commands = <String>[];
  @override
  Future<List<Map<String, dynamic>>> history(
    String organizationId,
    String customerId,
    int offset,
  ) async => [];
  @override
  Future<void> queue(
    String requestId,
    String organizationId,
    String invoiceId,
    String channel,
  ) async {
    commands.add('$requestId:$organizationId:$invoiceId:$channel');
    if (rejection != null) throw rejection!;
    throw StateError('Response lost');
  }
}

void main() {
  Widget app(_Queue queue) => ProviderScope(
    overrides: [reminderQueueRepositoryProvider.overrideWithValue(queue)],
    child: const MaterialApp(
      home: Scaffold(
        body: QueueReminderForm(
          organizationId: 'org-a',
          invoiceId: 'invoice-a',
        ),
      ),
    ),
  );
  testWidgets('server consent rejection is shown without a success claim', (
    tester,
  ) async {
    final queue = _Queue()
      ..rejection = const ReminderQueueFailure(
        'Record current customer consent before queueing.',
      );
    await tester.pumpWidget(app(queue));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue overdue reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue request'));
    await tester.pumpAndSettle();
    expect(
      find.text('Record current customer consent before queueing.'),
      findsOneWidget,
    );
    expect(
      find.text('Reminder queued. No message has been sent.'),
      findsNothing,
    );
  });
  testWidgets('cancelled confirmation never queues a reminder', (tester) async {
    final queue = _Queue();
    await tester.pumpWidget(app(queue));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue overdue reminder'));
    await tester.pumpAndSettle();
    expect(queue.commands, isEmpty);
    expect(find.textContaining('Delivery is not enabled yet'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(queue.commands, isEmpty);
  });
  testWidgets(
    'unchanged reminder retries original command after lost response',
    (tester) async {
      final queue = _Queue();
      await tester.pumpWidget(app(queue));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Queue overdue reminder'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Queue request'));
        await tester.pumpAndSettle();
      }
      expect(queue.commands.length, 2);
      expect(queue.commands.first, queue.commands.last);
      expect(queue.commands.first, endsWith(':org-a:invoice-a:email'));
    },
  );
}
