class FinancialReport {
  const FinancialReport(this.values);
  final Map<String, dynamic> values;
}

abstract interface class ReportRepository {
  Future<FinancialReport> stockValuation(String organizationId, int offset);
  Future<FinancialReport> exportStockValuation(
    String requestId,
    String organizationId,
  );
  Future<FinancialReport> customerAging(String organizationId, int offset);
  Future<FinancialReport> exportCustomerAging(
    String requestId,
    String organizationId,
  );
  Future<FinancialReport> export(
    String requestId,
    String organizationId,
    String kind,
    String from,
    String to,
  );
  Future<FinancialReport> page(
    String organizationId,
    String kind,
    String from,
    String to,
    int offset,
  );
}
