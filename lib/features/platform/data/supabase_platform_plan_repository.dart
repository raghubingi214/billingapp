import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/platform_plan_repository.dart';

class SupabasePlatformPlanRepository implements PlatformPlanRepository {
  SupabasePlatformPlanRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> createDraft(String requestId, Map<String, dynamic> data) async {
    await client.rpc(
      'create_platform_plan_draft',
      params: {'p_request_id': requestId, 'p_data': data},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> page(int offset) async {
    final rows = await client.rpc(
      'platform_plan_catalog',
      params: {'p_offset': offset},
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
