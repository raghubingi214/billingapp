import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/notifications/domain/notification_repository.dart';
import 'package:smart_billing/features/notifications/presentation/notifications_screen.dart';

class FakeNotifications implements NotificationRepository {
  bool read = false, fail = false;
  final filters = <bool>[];
  @override
  Future<List<BusinessNotification>> page(
    String org,
    int offset,
    bool unreadOnly,
  ) async {
    filters.add(unreadOnly);
    if (fail) throw StateError('Offline');
    if (unreadOnly && read) return [];
    return [
      BusinessNotification(
        'event',
        'Receipt recorded',
        'Details in your business',
        'payments',
        'receipt',
        read,
      ),
    ];
  }

  @override
  Future<void> markRead(String org, String id) async {
    read = true;
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeNotifications repository) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: NotificationsScreen(organizationId: 'org'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unread filter reloads after marking notification read', (
    tester,
  ) async {
    final repository = FakeNotifications();
    await open(tester, repository);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(repository.filters.last, true);
    await tester.tap(find.text('Receipt recorded'));
    await tester.pumpAndSettle();
    expect(repository.read, true);
    expect(find.text('No notifications'), findsOneWidget);
  });
  testWidgets('notification load failure offers retry', (tester) async {
    final repository = FakeNotifications()..fail = true;
    await open(tester, repository);
    expect(find.text('Unable to load notifications. Retry.'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Unable to load notifications. Retry.'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt recorded'), findsOneWidget);
  });
}
