import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/platform/domain/platform_repository.dart';
import 'package:smart_billing/features/platform/presentation/platform_screen.dart';

class _Repository implements PlatformRepository {
  bool allowed = false;
  List<Map<String, dynamic>> threadRows = [];
  @override
  Future<List<Map<String, dynamic>>> supportThread(
    String supportId,
    int offset,
  ) async => threadRows;
  int replyCalls = 0;
  bool failReply = false;
  final replyKeys = <String>[];
  @override
  Future<void> replyToSupport(
    String requestId,
    String supportId,
    String body,
  ) async {
    replyCalls++;
    replyKeys.add(requestId);
    if (failReply) throw StateError('Response lost');
  }

  int reviewCalls = 0;
  @override
  Future<void> beginSupportReview(String requestId, String supportId) async {
    reviewCalls++;
    rows = [];
  }

  int queueCalls = 0;
  @override
  Future<List<Map<String, dynamic>>> supportQueue(
    String status,
    int offset,
  ) async {
    queueCalls++;
    return rows;
  }

  int overviewCalls = 0;
  int businessCalls = 0;
  List<Map<String, dynamic>> rows = [];
  @override
  Future<List<Map<String, dynamic>>> businesses(int offset) async {
    businessCalls++;
    return rows;
  }

  @override
  Future<bool> hasAccess() async => allowed;
  @override
  Future<Map<String, dynamic>> overview() async {
    overviewCalls++;
    return {'businesses': 2};
  }
}

void main() {
  testWidgets('unchanged reply retains command key after lost response', (
    tester,
  ) async {
    final repository = _Repository()
      ..allowed = true
      ..failReply = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: PlatformReplyScreen(
            userId: 'admin',
            supportId: 'support-a',
            subject: 'Help request',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'We are reviewing your request.',
    );
    await tester.ensureVisible(find.text('Send reply'));
    await tester.tap(find.text('Send reply'));
    await tester.pumpAndSettle();
    expect(repository.replyCalls, 1);
    await tester.ensureVisible(find.text('Send reply'));
    await tester.tap(find.text('Send reply'));
    await tester.pumpAndSettle();
    expect(repository.replyKeys.length, 2);
    expect(repository.replyKeys.first, repository.replyKeys.last);
    expect(find.text('We are reviewing your request.'), findsOneWidget);
  });
  testWidgets('reply history disappears after platform access revocation', (
    tester,
  ) async {
    final repository = _Repository()
      ..allowed = true
      ..threadRows = [
        {'body': 'Earlier response'},
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: PlatformReplyScreen(
            userId: 'admin',
            supportId: 'support-a',
            subject: 'Help request',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Earlier response'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Earlier response'), findsNothing);
    expect(
      find.text('Platform access is not enabled for this account.'),
      findsOneWidget,
    );
  });
  testWidgets('platform reply validates before sending', (tester) async {
    final repository = _Repository()..allowed = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: PlatformReplyScreen(
            userId: 'admin',
            supportId: 'support-a',
            subject: 'Help request',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send reply'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a response'), findsOneWidget);
    expect(repository.replyCalls, 0);
  });
  testWidgets('support review requires confirmation and refreshes queue', (
    tester,
  ) async {
    final repository = _Repository()
      ..allowed = true
      ..rows = [
        {
          'id': 'support-a',
          'subject': 'Help request',
          'business_name': 'Shop',
          'kind': 'help',
          'message': 'Please help with this request.',
          'status': 'open',
        },
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PlatformSupportScreen(userId: 'admin')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start review'));
    await tester.pumpAndSettle();
    expect(repository.reviewCalls, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Start review').last);
    await tester.pumpAndSettle();
    expect(repository.reviewCalls, 1);
    expect(find.text('No requests on this page.'), findsOneWidget);
  });
  testWidgets('resume clears directory after access is revoked', (
    tester,
  ) async {
    final repository = _Repository()
      ..allowed = true
      ..rows = [
        {'name': 'Example shop', 'status': 'active', 'staff_count': 3},
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: PlatformBusinessesScreen(userId: 'admin'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Example shop'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Example shop'), findsNothing);
    expect(find.text('Retry access and load'), findsOneWidget);
    expect(repository.businessCalls, 1);
  });
  testWidgets('resume removes overview after platform access is revoked', (
    tester,
  ) async {
    final repository = _Repository()..allowed = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: PlatformScreen(userId: 'admin')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Platform overview'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Platform overview'), findsNothing);
    expect(
      find.text('Platform access is not enabled for this account.'),
      findsOneWidget,
    );
  });
  test('denied account never requests platform overview', () async {
    final repository = _Repository();
    final container = ProviderContainer(
      overrides: [platformRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(platformOverviewProvider('merchant').future),
      throwsStateError,
    );
    expect(repository.overviewCalls, 0);
    await expectLater(
      container.read(
        platformBusinessesProvider((userId: 'merchant', offset: 0)).future,
      ),
      throwsStateError,
    );
    expect(repository.businessCalls, 0);
    await expectLater(
      container.read(
        platformSupportProvider((
          userId: 'merchant',
          status: 'open',
          offset: 0,
        )).future,
      ),
      throwsStateError,
    );
    expect(repository.queueCalls, 0);
  });

  test('revoking access invalidates previously loaded overview', () async {
    final repository = _Repository()..allowed = true;
    final container = ProviderContainer(
      overrides: [platformRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      platformOverviewProvider('admin'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(await container.read(platformOverviewProvider('admin').future), {
      'businesses': 2,
    });
    repository.allowed = false;
    container.invalidate(platformAccessProvider('admin'));
    await expectLater(
      container.read(platformOverviewProvider('admin').future),
      throwsStateError,
    );
    expect(repository.overviewCalls, 1);
  });
}
