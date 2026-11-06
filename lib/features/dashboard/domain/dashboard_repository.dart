class DashboardSummary {
  const DashboardSummary(
    this.sales,
    this.collections,
    this.outstanding,
    this.lowStock,
    this.refreshedAt,
    this.cashierScope,
  );
  final String sales, collections, outstanding, refreshedAt;
  final int lowStock;
  final bool cashierScope;
}

abstract interface class DashboardRepository {
  Future<DashboardSummary> summary(
    String organizationId,
    String from,
    String to,
  );
}
