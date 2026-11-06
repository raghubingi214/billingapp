class Customer {
  const Customer(this.id, this.version, this.values);
  final String id;
  final int version;
  final Map<String, Object?> values;
  String get name => values['name'] as String;
}

abstract interface class CustomerRepository {
  Future<List<Customer>> page(String organizationId, int offset);
  Future<void> save(
    String requestId,
    String organizationId,
    Customer? previous,
    Map<String, Object?> values,
  );
}
