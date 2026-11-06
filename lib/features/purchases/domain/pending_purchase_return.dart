import 'purchase_detail_repository.dart';

class PendingPurchaseReturn {
  PendingPurchaseReturn({
    required this.requestId,
    required this.organizationId,
    required this.purchaseId,
    required this.reason,
    required this.reference,
    required List<Map<String, String>> items,
  }) : items = List.unmodifiable(
         items.map((item) => Map<String, String>.unmodifiable(item)),
       );
  final String requestId, organizationId, purchaseId, reason;
  final String? reference;
  final List<Map<String, String>> items;

  Map<String, Object?> toJson() => {
    'version': 1,
    'request_id': requestId,
    'organization_id': organizationId,
    'purchase_id': purchaseId,
    'reason': reason,
    'reference': reference,
    'items': items,
  };

  factory PendingPurchaseReturn.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) {
      throw const FormatException('Unknown return version');
    }
    final raw = data['items'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Missing return lines');
    }
    return PendingPurchaseReturn(
      requestId: data['request_id'] as String,
      organizationId: data['organization_id'] as String,
      purchaseId: data['purchase_id'] as String,
      reason: data['reason'] as String,
      reference: data['reference'] as String?,
      items: [for (final row in raw) Map<String, String>.from(row as Map)],
    );
  }

  Future<void> send(PurchaseDetailRepository repository) =>
      repository.returnPurchase(
        requestId,
        organizationId,
        purchaseId,
        reason,
        reference,
        items,
      );
}

abstract interface class PendingPurchaseReturnStore {
  Future<void> save(String actorId, PendingPurchaseReturn command);
  Future<PendingPurchaseReturn?> load(
    String actorId,
    String organizationId,
    String purchaseId,
  );
  Future<void> clear(String actorId, String organizationId, String purchaseId);
}
