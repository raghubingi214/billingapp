import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/sales_repository.dart';

class SupabaseSalesRepository implements SalesRepository {
  SupabaseSalesRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<SalesInvoice>> page(String organizationId, int offset) async {
    final rows = await client
        .from('sales_invoices')
        .select('id,invoice_number,grand_total,invoice_date')
        .eq('organization_id', organizationId)
        .order('issued_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (r) => SalesInvoice(
            r['id'] as String,
            r['invoice_number'] as String,
            r['grand_total'].toString(),
            r['invoice_date'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<SalesDetail> detail(String organizationId, String invoiceId) async {
    final result = await client.rpc(
      'sales_invoice_detail',
      params: {'p_organization_id': organizationId, 'p_invoice_id': invoiceId},
    );
    return SalesDetail(Map<String, dynamic>.from(result as Map));
  }
}
