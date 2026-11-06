import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/notification_repository.dart';

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<BusinessNotification>> page(
    String organizationId,
    int offset,
    bool unreadOnly,
  ) async {
    var query = client
        .from('notifications')
        .select('id,title,body,entity_type,entity_id,read_at')
        .eq('organization_id', organizationId);
    if (unreadOnly) query = query.isFilter('read_at', null);
    final rows = await query
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows
        .map(
          (r) => BusinessNotification(
            r['id'] as String,
            r['title'] as String,
            r['body'] as String,
            r['entity_type'] as String,
            r['entity_id'] as String,
            r['read_at'] != null,
          ),
        )
        .toList();
  }

  @override
  Future<void> markRead(String organizationId, String notificationId) async {
    await client.rpc(
      'mark_notification_read',
      params: {
        'p_organization_id': organizationId,
        'p_notification_id': notificationId,
      },
    );
  }
}
