import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/audit_repository.dart';

class SupabaseAuditRepository implements AuditRepository {
  SupabaseAuditRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<AuditEvent>> page(String organizationId, int offset) async {
    final rows = await client
        .from('audit_events')
        .select(
          'action,created_at,actor_user_id,record_id,before_data,after_data',
        )
        .eq('organization_id', organizationId)
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (r) => AuditEvent(
            r['action'] as String,
            r['created_at'] as String,
            r['actor_user_id'] as String,
            r['record_id'] as String,
            (r['before_data'] as Map?)?.cast<String, dynamic>(),
            (r['after_data'] as Map?)?.cast<String, dynamic>(),
          ),
        )
        .toList();
  }
}
