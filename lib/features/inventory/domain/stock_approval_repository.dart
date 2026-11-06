class StockApproval {
  const StockApproval(
    this.id,
    this.product,
    this.outlet,
    this.quantity,
    this.reason,
    this.status,
  );
  final String id, product, outlet, quantity, reason, status;
}

abstract interface class StockApprovalRepository {
  Future<void> request(
    String key,
    String org,
    String outlet,
    String product,
    int version,
    String quantity,
    String reason,
  );
  Future<List<StockApproval>> page(String org, int offset);
  Future<void> review(String key, String org, String id, bool approve);
}
