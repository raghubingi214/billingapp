class Supplier {
  const Supplier(this.id, this.version, this.values);
  final String id;
  final int version;
  final Map<String, Object?> values;
  String get name => values['name'] as String;
}

abstract interface class SupplierRepository {
  Future<List<Supplier>> page(String organizationId, int offset);
  Future<void> save(
    String requestId,
    String organizationId,
    Supplier? previous,
    Map<String, Object?> values,
  );
}
