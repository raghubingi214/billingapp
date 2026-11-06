class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.version,
    required this.name,
    required this.type,
    required this.values,
  });
  final String id, name, type;
  final int version;
  final Map<String, Object?> values;
}

abstract interface class CatalogRepository {
  Future<List<CatalogProduct>> page(
    String organizationId,
    int offset, {
    required bool archived,
    String query = '',
  });
  Future<void> save(
    String requestId,
    String organizationId,
    CatalogProduct? previous,
    Map<String, Object?> values,
  );
}
