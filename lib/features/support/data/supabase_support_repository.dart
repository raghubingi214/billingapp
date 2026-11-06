import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/support_repository.dart';

class SupabaseSupportRepository implements SupportRepository {
  SupabaseSupportRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Map<String, dynamic>>> replies(
    String organizationId,
    String supportId,
    int offset,
  ) async => await client
      .from('support_replies')
      .select('id,body,created_at')
      .eq('organization_id', organizationId)
      .eq('support_id', supportId)
      .order('created_at')
      .order('id')
      .range(offset, offset + 49);
  @override
  Future<List<Map<String, dynamic>>> history(
    String organizationId,
    int offset,
  ) async => await client
      .from('support_requests')
      .select('id,kind,subject,status,created_at')
      .eq('organization_id', organizationId)
      .order('created_at', ascending: false)
      .order('id')
      .range(offset, offset + 49);
  @override
  Future<void> submit(
    String requestId,
    String organizationId,
    String kind,
    String subject,
    String message,
  ) async {
    await client.rpc(
      'submit_support_request',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_kind': kind,
        'p_subject': subject,
        'p_message': message,
      },
    );
  }
}
