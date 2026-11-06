import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/inventory_repository.dart';

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<StockOutlet>> outlets(String organizationId) async {
    final rows = await client
        .from('outlets')
        .select('id,name')
        .eq('organization_id', organizationId)
        .eq('active', true)
        .order('id')
        .limit(100);
    return rows
        .map((r) => StockOutlet(r['id'] as String, r['name'] as String))
        .toList();
  }

  @override
  Future<List<StockPosition>> positions(
    String organizationId,
    String outletId,
    int offset, {
    bool lowOnly = false,
  }) async {
    final rows = await client.rpc(
      'inventory_positions',
      params: {
        'p_organization_id': organizationId,
        'p_outlet_id': outletId,
        'p_offset': offset,
        'p_low_only': lowOnly,
      },
    );
    return (rows as List)
        .map(
          (r) => StockPosition(
            r['product_id'] as String,
            r['name'] as String,
            r['unit'] as String,
            r['quantity_on_hand'].toString(),
            r['version'] as int,
          ),
        )
        .toList();
  }

  @override
  Future<List<StockMovement>> movements(
    String organizationId,
    String outletId,
    String productId,
    int offset,
  ) async {
    final rows = await client
        .from('stock_movements')
        .select('signed_qty,reason,created_at')
        .eq('organization_id', organizationId)
        .eq('outlet_id', outletId)
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (r) => StockMovement(
            r['signed_qty'].toString(),
            r['reason'] as String,
            r['created_at'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> count(
    String requestId,
    String organizationId,
    String outletId,
    StockPosition position,
    String quantity,
    String reason,
  ) async {
    await client.rpc(
      'post_stock_count',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_outlet_id': outletId,
        'p_product_id': position.productId,
        'p_expected_version': position.version,
        'p_counted_qty': quantity,
        'p_reason': reason,
      },
    );
  }
}
