import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/refund_repository.dart';

class SupabaseRefundRepository implements RefundRepository {
  SupabaseRefundRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> record(
    String requestId,
    String organizationId,
    String invoiceId,
    String amount,
    String method,
    String reference,
    String reason,
  ) async {
    await client.rpc(
      'refund_sale',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_invoice_id': invoiceId,
        'p_amount': amount,
        'p_method': method,
        'p_reference': reference,
        'p_reason': reason,
      },
    );
  }
}
