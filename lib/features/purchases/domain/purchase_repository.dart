class PurchaseChoice {
  const PurchaseChoice(this.id, this.name);
  final String id, name;
}

class PurchaseSummary {
  const PurchaseSummary(this.id, this.number, this.total, this.date);
  final String id, number, total, date;
}

abstract interface class PurchaseRepository {
  Future<List<PurchaseChoice>> choices(String organizationId, String type);
  Future<List<PurchaseSummary>> page(String organizationId, int offset);
  Future<void> receive(
    String requestId,
    String organizationId,
    String outletId,
    String supplierId,
    String billNo,
    String date,
    List<Map<String, String>> items,
  );
}
