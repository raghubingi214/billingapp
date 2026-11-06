import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/return_repository.dart';

class SupabaseReturnRepository implements ReturnRepository {
  SupabaseReturnRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> post(
    String requestId,
    String organizationId,
    String invoiceId,
    String reason,
    List<Map<String, Object?>> items,
  ) async {
    await client.rpc(
      'return_sale',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_invoice_id': invoiceId,
        'p_reason': reason,
        'p_items': items,
      },
    );
  }
}
