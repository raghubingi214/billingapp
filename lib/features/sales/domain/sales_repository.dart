class SalesInvoice {
  const SalesInvoice(this.id, this.number, this.total, this.date);
  final String id, number, total, date;
}

class SalesDetail {
  const SalesDetail(this.values);
  final Map<String, dynamic> values;
}

abstract interface class SalesRepository {
  Future<List<SalesInvoice>> page(String organizationId, int offset);
  Future<SalesDetail> detail(String organizationId, String invoiceId);
}
