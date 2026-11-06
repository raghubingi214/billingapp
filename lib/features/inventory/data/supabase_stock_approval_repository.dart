import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/stock_approval_repository.dart';

class SupabaseStockApprovalRepository implements StockApprovalRepository {
  SupabaseStockApprovalRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> request(
    String key,
    String org,
    String outlet,
    String product,
    int version,
    String quantity,
    String reason,
  ) async {
    await client.rpc(
      'request_stock_adjustment',
      params: {
        'p_request_id': key,
        'p_organization_id': org,
        'p_outlet_id': outlet,
        'p_product_id': product,
        'p_expected_version': version,
        'p_counted_qty': quantity,
        'p_reason': reason,
      },
    );
  }

  @override
  Future<List<StockApproval>> page(String org, int offset) async {
    final rows = await client
        .from('stock_adjustment_requests')
        .select('id,counted_qty,reason,status,products(name),outlets(name)')
        .eq('organization_id', org)
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (r) => StockApproval(
            r['id'] as String,
            (r['products'] as Map?)?['name'] as String? ?? 'Product',
            (r['outlets'] as Map?)?['name'] as String? ?? 'Outlet',
            r['counted_qty'].toString(),
            r['reason'] as String,
            r['status'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> review(String key, String org, String id, bool approve) async {
    await client.rpc(
      'review_stock_adjustment',
      params: {
        'p_request_id': key,
        'p_organization_id': org,
        'p_adjustment_id': id,
        'p_approve': approve,
      },
    );
  }
}
