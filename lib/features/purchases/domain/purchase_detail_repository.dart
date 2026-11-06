class PurchaseDetail {
  const PurchaseDetail(this.values);
  final Map<String, dynamic> values;
}

abstract interface class PurchaseDetailRepository {
  Future<PurchaseDetail> detail(String organizationId, String purchaseId);
  Future<Map<String, dynamic>> previewReturn(
    String organizationId,
    String purchaseId,
    List<Map<String, String>> items,
  );
  Future<void> returnPurchase(
    String requestId,
    String organizationId,
    String purchaseId,
    String reason,
    String? reference,
    List<Map<String, String>> items,
  );
  Future<void> recordSupplierCreditRefund(
    String requestId,
    String organizationId,
    String purchaseId,
    String amount,
    String date,
    String method,
    String? reference,
  );
  Future<void> pay(
    String requestId,
    String organizationId,
    String supplierId,
    String purchaseId,
    String amount,
    String method,
    String reference,
    String date,
  );
}
