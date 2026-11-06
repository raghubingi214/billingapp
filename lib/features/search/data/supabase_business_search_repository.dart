import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/business_search_repository.dart';

class SupabaseBusinessSearchRepository implements BusinessSearchRepository {
  SupabaseBusinessSearchRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<BusinessSearchResult>> search(
    String organizationId,
    SearchCategory category,
    String query,
    int offset,
  ) async {
    if (query.trim().length < 2 || query.length > 100 || offset < 0) {
      throw ArgumentError('Invalid search');
    }
    if (category == SearchCategory.products) {
      final result = await client.rpc(
        'search_products',
        params: {
          'p_organization_id': organizationId,
          'p_query': query.trim(),
          'p_archived': false,
          'p_offset': offset,
        },
      );
      return (result as List)
          .map(
            (row) => BusinessSearchResult(
              row['id'] as String,
              row['name'] as String,
              '${row['sku'] ?? ''} · ${row['barcode'] ?? ''}',
            ),
          )
          .toList();
    }
    final pattern =
        '%${query.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    if (category == SearchCategory.invoices) {
      final rows = await client
          .from('sales_invoices')
          .select('id,invoice_number,invoice_date,grand_total')
          .eq('organization_id', organizationId)
          .ilike('invoice_number', pattern)
          .order('issued_at', ascending: false)
          .order('id')
          .range(offset, offset + 49);
      return rows
          .map(
            (row) => BusinessSearchResult(
              row['id'] as String,
              row['invoice_number'] as String,
              '${row['invoice_date']} · INR ${row['grand_total']}',
            ),
          )
          .toList();
    }
    final rows = await client
        .from('customers')
        .select('id,name,phone')
        .eq('organization_id', organizationId)
        .ilike('name', pattern)
        .order('name')
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (row) => BusinessSearchResult(
            row['id'] as String,
            row['name'] as String,
            '${row['phone'] ?? ''}',
          ),
        )
        .toList();
  }
}
