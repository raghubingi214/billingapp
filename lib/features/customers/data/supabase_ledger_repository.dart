import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/ledger_repository.dart';

class SupabaseLedgerRepository implements LedgerRepository {
  SupabaseLedgerRepository(this.client);
  final SupabaseClient client;
  @override
  Future<CustomerLedger> page(
    String organizationId,
    String customerId,
    String from,
    String to,
    int offset,
  ) async {
    final result = await client.rpc(
      'customer_ledger',
      params: {
        'p_organization_id': organizationId,
        'p_customer_id': customerId,
        'p_from': from,
        'p_to': to,
        'p_offset': offset,
      },
    );
    return CustomerLedger(Map<String, dynamic>.from(result as Map));
  }
}
