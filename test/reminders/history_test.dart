import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/reminders/domain/reminder_queue_repository.dart';
import 'package:smart_billing/features/reminders/presentation/reminder_history_screen.dart';

class _Queue implements ReminderQueueRepository {
  @override
  Future<void> queue(
    String requestId,
    String organizationId,
    String invoiceId,
    String channel,
  ) async {}
  String? scope;
  @override
  Future<List<Map<String, dynamic>>> history(
    String organizationId,
    String customerId,
    int offset,
  ) async {
    scope = '$organizationId:$customerId:$offset';
    return [
      {
        'channel': 'email',
        'state': 'cancelled',
        'created_at': '2026-11-06T00:00:00Z',
      },
    ];
  }
}

void main() {
  testWidgets('history uses customer scope and displays cancelled state', (
    tester,
  ) async {
    final queue = _Queue();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reminderQueueRepositoryProvider.overrideWithValue(queue)],
        child: const MaterialApp(
          home: ReminderHistoryScreen(
            organizationId: 'org-a',
            customerId: 'customer-a',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(queue.scope, 'org-a:customer-a:0');
    expect(find.text('email · Cancelled'), findsOneWidget);
    expect(find.textContaining('does not confirm'), findsOneWidget);
  });
}
