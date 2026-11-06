import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/purchases/data/shared_preferences_pending_return_store.dart';
import 'package:smart_billing/features/purchases/domain/pending_purchase_return.dart';

void main() {
  test(
    'pending purchase return persists with actor, business and purchase scope',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesPendingReturnStore();
      final command = PendingPurchaseReturn(
        requestId: 'request',
        organizationId: 'org',
        purchaseId: 'purchase',
        reason: 'Damaged goods',
        reference: null,
        items: [
          {'purchase_item_id': 'item', 'qty': '1'},
        ],
      );
      await store.save('owner', command);
      expect(
        (await store.load('owner', 'org', 'purchase'))?.toJson(),
        command.toJson(),
      );
      expect(await store.load('other-user', 'org', 'purchase'), isNull);
      expect(await store.load('owner', 'other-org', 'purchase'), isNull);
      expect(await store.load('owner', 'org', 'other-purchase'), isNull);
      await store.clear('owner', 'org', 'purchase');
      expect(await store.load('owner', 'org', 'purchase'), isNull);
    },
  );
}
