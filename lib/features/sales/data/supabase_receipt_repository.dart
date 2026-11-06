import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/receipt_repository.dart';

class SupabaseReceiptRepository implements ReceiptRepository {
  SupabaseReceiptRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> record(
    String requestId,
    String organizationId,
    String customerId,
    String invoiceId,
    String amount,
    String method,
    String reference,
    String date,
  ) async {
    await client.rpc(
      'record_receipt',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_customer_id': customerId,
        'p_amount': amount,
        'p_date': date,
        'p_method': method,
        'p_reference': reference,
        'p_allocations': [
          {'invoice_id': invoiceId, 'amount': amount},
        ],
      },
    );
  }
}
