import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/notifications/domain/notification_repository.dart';
import 'package:smart_billing/features/notifications/presentation/notifications_screen.dart';

class _Notifications implements NotificationRepository {
  bool fail = false;
  int count = 0, marks = 0;
  Completer<void>? pending;
  final offsets = <int>[];
  @override
  Future<List<BusinessNotification>> page(
    String organizationId,
    int offset,
    bool unreadOnly,
  ) async {
    offsets.add(offset);
    if (fail) throw StateError('Connection lost');
    return [
      for (var i = 0; i < count; i++)
        BusinessNotification(
          'n-${offset + i}',
          'Alert ${offset + i}',
          'Review this business update.',
          'notice',
          'entity',
          false,
        ),
    ];
  }

  @override
  Future<void> markRead(String organizationId, String notificationId) async {
    marks++;
    await pending?.future;
  }
}

Future<void> _open(WidgetTester tester, _Notifications repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(
        home: NotificationsScreen(organizationId: 'org'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('load failure shows retry without empty or paging claims', (
    tester,
  ) async {
    final repository = _Notifications()..fail = true;
    await _open(tester, repository);
    expect(find.text('No notifications'), findsNothing);
    expect(find.text('Load more'), findsNothing);
    repository.fail = false;
    await tester.tap(find.text('Unable to load notifications. Retry.'));
    await tester.pumpAndSettle();
    expect(find.text('No notifications'), findsOneWidget);
    expect(repository.offsets, [0, 0]);
    expect(
      tester.widget<ListView>(find.byType(ListView)).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
  });
  testWidgets(
    'pending open blocks duplicate taps and can retry after failure',
    (tester) async {
      final repository = _Notifications()
        ..count = 1
        ..pending = Completer<void>();
      await _open(tester, repository);
      await tester.tap(find.text('Alert 0'));
      await tester.pump();
      await tester.tap(find.text('Alert 0'));
      await tester.pump();
      expect(repository.marks, 1);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      repository.pending!.completeError(StateError('Access changed'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Notification unavailable. Your business access may have changed.',
        ),
        findsOneWidget,
      );
      repository.pending = null;
      await tester.tap(find.text('Alert 0'));
      await tester.pumpAndSettle();
      expect(repository.marks, 2);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
    },
  );
  testWidgets(
    'failed page retries same offset and retains earlier notifications',
    (tester) async {
      final repository = _Notifications()..count = 50;
      await _open(tester, repository);
      await tester.scrollUntilVisible(find.text('Load more'), 600);
      await tester.ensureVisible(find.text('Load more'));
      await tester.pumpAndSettle();
      repository.fail = true;
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(repository.offsets, [0, 50]);
      expect(find.text('Load more'), findsNothing);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Alert 0'), findsOneWidget);
      repository.fail = false;
      repository.count = 1;
      await tester.tap(find.text('Unable to load notifications. Retry.'));
      await tester.pumpAndSettle();
      expect(repository.offsets, [0, 50, 50]);
    },
  );
}
