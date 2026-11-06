import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/platform/data/shared_preferences_pending_plan_store.dart';
import 'package:smart_billing/features/platform/domain/pending_plan_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'pending plan survives store recreation and is scoped to actor',
    () async {
      final store = SharedPreferencesPendingPlanStore();
      await store.save(
        'admin-a',
        const PendingPlanDraft('command', {'code': 'starter'}),
      );
      final reopened = SharedPreferencesPendingPlanStore();
      expect(await reopened.load('admin-b'), isNull);
      final saved = await reopened.load('admin-a');
      expect(saved!.requestId, 'command');
      expect(saved.data['code'], 'starter');
      await reopened.clear('admin-b');
      expect(await reopened.load('admin-a'), isNotNull);
      await reopened.clear('admin-a');
      expect(await reopened.load('admin-a'), isNull);
    },
  );
  test('missing actor cannot read or save a pending command', () async {
    final store = SharedPreferencesPendingPlanStore();
    await expectLater(store.load(''), throwsStateError);
    await expectLater(
      store.save('', const PendingPlanDraft('command', {})),
      throwsStateError,
    );
  });
}
