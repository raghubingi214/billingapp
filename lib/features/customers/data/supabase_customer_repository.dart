import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/customer_repository.dart';

class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Customer>> page(String organizationId, int offset) async {
    final rows = await client
        .from('customers')
        .select()
        .eq('organization_id', organizationId)
        .order('name')
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map((row) => Customer(row['id'] as String, row['version'] as int, row))
        .toList();
  }

  @override
  Future<void> save(
    String requestId,
    String organizationId,
    Customer? previous,
    Map<String, Object?> values,
  ) async {
    await client.rpc(
      'save_customer',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_customer_id': previous?.id,
        'p_version': previous?.version,
        'p_data': values,
      },
    );
  }
}
