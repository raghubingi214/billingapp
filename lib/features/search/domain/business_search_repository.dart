enum SearchCategory { products, invoices, customers }

class BusinessSearchResult {
  const BusinessSearchResult(this.id, this.title, this.subtitle);
  final String id, title, subtitle;
}

abstract interface class BusinessSearchRepository {
  Future<List<BusinessSearchResult>> search(
    String organizationId,
    SearchCategory category,
    String query,
    int offset,
  );
}
