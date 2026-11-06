import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/purchase_repository.dart';

class SupabasePurchaseRepository implements PurchaseRepository {
  SupabasePurchaseRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<PurchaseChoice>> choices(
    String organizationId,
    String type,
  ) async {
    if (!['outlets', 'suppliers', 'products'].contains(type)) {
      throw ArgumentError('Invalid choice type');
    }
    final result = <PurchaseChoice>[];
    for (var offset = 0; ; offset += 100) {
      var query = client
          .from(type)
          .select('id,name')
          .eq('organization_id', organizationId)
          .eq('active', true);
      if (type == 'products') query = query.eq('type', 'product');
      final rows = await query
          .order('name')
          .order('id')
          .range(offset, offset + 99);
      result.addAll(
        rows.map((r) => PurchaseChoice(r['id'] as String, r['name'] as String)),
      );
      if (rows.length < 100) return result;
    }
  }

  @override
  Future<List<PurchaseSummary>> page(String organizationId, int offset) async {
    final rows = await client
        .from('purchases')
        .select('id,supplier_bill_no,grand_total,bill_date')
        .eq('organization_id', organizationId)
        .order('posted_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (r) => PurchaseSummary(
            r['id'] as String,
            r['supplier_bill_no'] as String,
            r['grand_total'].toString(),
            r['bill_date'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> receive(
    String requestId,
    String organizationId,
    String outletId,
    String supplierId,
    String billNo,
    String date,
    List<Map<String, String>> items,
  ) async {
    await client.rpc(
      'receive_purchase',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_outlet_id': outletId,
        'p_supplier_id': supplierId,
        'p_bill_no': billNo,
        'p_bill_date': date,
        'p_items': items,
      },
    );
  }
}
