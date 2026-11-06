import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/pending_purchase_return.dart';

class SharedPreferencesPendingReturnStore
    implements PendingPurchaseReturnStore {
  static String key(String actor, String org, String purchase) =>
      'pending_purchase_return_v1:$actor:$org:$purchase';
  @override
  Future<void> save(String actorId, PendingPurchaseReturn command) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key(actorId, command.organizationId, command.purchaseId),
      jsonEncode(command.toJson()),
    )) {
      throw StateError('Unable to save pending return');
    }
  }

  @override
  Future<PendingPurchaseReturn?> load(
    String actorId,
    String organizationId,
    String purchaseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key(actorId, organizationId, purchaseId));
    if (raw == null) return null;
    final command = PendingPurchaseReturn.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (command.organizationId != organizationId ||
        command.purchaseId != purchaseId) {
      throw const FormatException('Pending return scope mismatch');
    }
    return command;
  }

  @override
  Future<void> clear(
    String actorId,
    String organizationId,
    String purchaseId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(key(actorId, organizationId, purchaseId))) {
      throw StateError('Unable to clear pending return');
    }
  }
}
