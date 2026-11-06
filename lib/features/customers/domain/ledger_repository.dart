class CustomerLedger {
  const CustomerLedger(this.values);
  final Map<String, dynamic> values;
}

abstract interface class LedgerRepository {
  Future<CustomerLedger> page(
    String organizationId,
    String customerId,
    String from,
    String to,
    int offset,
  );
}
