import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/support/data/shared_preferences_pending_support_store.dart';
import 'package:smart_billing/features/support/domain/pending_support_request.dart';

void main() {
  test(
    'pending support survives a new store and is actor/tenant isolated',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesPendingSupportStore();
      await store.save(
        'actor-a',
        const PendingSupportRequest(
          'request-id',
          'org-a',
          'help',
          'Subject',
          'Request details',
        ),
      );
      final restored = await SharedPreferencesPendingSupportStore().load(
        'actor-a',
        'org-a',
      );
      expect(restored?.requestId, 'request-id');
      expect(restored?.message, 'Request details');
      expect(await store.load('actor-b', 'org-a'), isNull);
      expect(await store.load('actor-a', 'org-b'), isNull);
      await store.clear('actor-a', 'org-a');
      expect(await store.load('actor-a', 'org-a'), isNull);
    },
  );
}
