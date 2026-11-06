class SaleOption {
  const SaleOption(this.id, this.name, {this.barcode, this.sku});
  final String id, name;
  final String? barcode, sku;
}

class SaleDraft {
  const SaleDraft(this.values);
  final Map<String, dynamic> values;
}

abstract interface class DraftRepository {
  Future<void> checkout(
    String requestId,
    String organizationId,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String dueDate,
    List<Map<String, String>> tenders,
  );
  Future<List<SaleOption>> options(String organizationId, String type);
  Future<List<SaleDraft>> drafts(String organizationId, int offset);
  Future<SaleDraft> save(
    String requestId,
    String organizationId,
    SaleDraft? previous,
    String outletId,
    String? customerId,
    String state,
    List<Map<String, String>> items,
    String notes,
  );
  Future<Map<String, dynamic>> quote(String organizationId, SaleDraft draft);
  Future<void> issue(
    String requestId,
    String organizationId,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String dueDate,
  );
}
