import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/platform_repository.dart';

class SupabasePlatformRepository implements PlatformRepository {
  SupabasePlatformRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Map<String, dynamic>>> supportThread(
    String supportId,
    int offset,
  ) async {
    final rows = await client.rpc(
      'platform_support_thread',
      params: {'p_support_id': supportId, 'p_offset': offset},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<void> replyToSupport(
    String requestId,
    String supportId,
    String body,
  ) async {
    await client.rpc(
      'reply_to_support',
      params: {
        'p_request_id': requestId,
        'p_support_id': supportId,
        'p_body': body,
      },
    );
  }

  @override
  Future<void> beginSupportReview(String requestId, String supportId) async {
    await client.rpc(
      'begin_support_review',
      params: {'p_request_id': requestId, 'p_support_id': supportId},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> supportQueue(
    String status,
    int offset,
  ) async {
    final rows = await client.rpc(
      'platform_support_queue',
      params: {'p_status': status, 'p_offset': offset},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> businesses(int offset) async {
    final rows = await client.rpc(
      'platform_businesses',
      params: {'p_offset': offset},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  @override
  Future<bool> hasAccess() async =>
      await client.rpc('platform_admin_status') == true;

  @override
  Future<Map<String, dynamic>> overview() async =>
      Map<String, dynamic>.from(await client.rpc('platform_overview') as Map);
}
