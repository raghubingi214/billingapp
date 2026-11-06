import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/reminder_consent_repository.dart';

class SupabaseReminderConsentRepository implements ReminderConsentRepository {
  SupabaseReminderConsentRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Map<String, dynamic>>> load(
    String organizationId,
    String customerId,
  ) async {
    final rows = await client
        .from('customer_reminder_consent')
        .select(
          'channel,allowed,recipient,evidence,version,updated_at,customers(email,phone)',
        )
        .eq('organization_id', organizationId)
        .eq('customer_id', customerId);
    return rows.map((row) {
      final customer = row['customers'] as Map<String, dynamic>?;
      final current = row['channel'] == 'email'
          ? '${customer?['email'] ?? ''}'.trim().toLowerCase()
          : '${customer?['phone'] ?? ''}'.trim();
      return {...row, 'current_recipient': current};
    }).toList();
  }

  @override
  Future<void> save(
    String requestId,
    String organizationId,
    String customerId,
    String channel,
    bool allowed,
    String evidence,
    int version,
  ) async {
    await client.rpc(
      'set_reminder_consent',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_customer_id': customerId,
        'p_channel': channel,
        'p_allowed': allowed,
        'p_evidence': evidence,
        'p_version': version,
      },
    );
  }
}
