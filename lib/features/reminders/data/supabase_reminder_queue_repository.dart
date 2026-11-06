import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/reminder_queue_repository.dart';

class SupabaseReminderQueueRepository implements ReminderQueueRepository {
  SupabaseReminderQueueRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> queue(
    String requestId,
    String organizationId,
    String invoiceId,
    String channel,
  ) async {
    try {
      await client.rpc(
        'queue_customer_reminder',
        params: {
          'p_request_id': requestId,
          'p_organization_id': organizationId,
          'p_invoice_id': invoiceId,
          'p_channel': channel,
        },
      );
    } on PostgrestException catch (error) {
      final message = switch (error.message) {
        'REMINDER_CONSENT_REQUIRED' =>
          'Record current customer consent for this channel before queueing a reminder.',
        'REMINDER_COOLDOWN' =>
          'A reminder was requested for this customer and channel within the last 24 hours. Try later.',
        'INVOICE_NOT_OVERDUE' => 'This invoice is not overdue yet.',
        'INVOICE_ALREADY_SETTLED' =>
          'This invoice has no outstanding balance. Refresh the invoice.',
        'ACCESS_DENIED' => 'Your current business role cannot queue reminders.',
        'REMINDER_INVOICE_UNAVAILABLE' =>
          'This invoice is unavailable or has no customer.',
        _ => null,
      };
      if (message != null) throw ReminderQueueFailure(message);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> history(
    String organizationId,
    String customerId,
    int offset,
  ) async => await client
      .from('customer_reminder_jobs')
      .select('id,invoice_id,channel,state,created_at')
      .eq('organization_id', organizationId)
      .eq('customer_id', customerId)
      .order('created_at', ascending: false)
      .order('id')
      .range(offset, offset + 49);
}
