import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/supplier_repository.dart';

class SupabaseSupplierRepository implements SupplierRepository {
  SupabaseSupplierRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Supplier>> page(String organizationId, int offset) async {
    final rows = await client
        .from('suppliers')
        .select()
        .eq('organization_id', organizationId)
        .order('name')
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map((row) => Supplier(row['id'] as String, row['version'] as int, row))
        .toList();
  }

  @override
  Future<void> save(
    String requestId,
    String organizationId,
    Supplier? previous,
    Map<String, Object?> values,
  ) async {
    await client.rpc(
      'save_supplier',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_supplier_id': previous?.id,
        'p_version': previous?.version,
        'p_data': values,
      },
    );
  }
}
