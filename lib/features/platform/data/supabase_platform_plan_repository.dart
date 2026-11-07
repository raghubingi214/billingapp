import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/platform_plan_repository.dart';

class SupabasePlatformPlanRepository implements PlatformPlanRepository {
  SupabasePlatformPlanRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> subscriptionOptions(
    String organizationId,
  ) async {
    final result = await client.rpc(
      'platform_subscription_options',
      params: {'p_organization_id': organizationId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> assignSubscription(
    String requestId,
    String organizationId,
    String planId,
    int? expectedVersion,
  ) async {
    await client.rpc(
      'assign_platform_subscription',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_plan_id': planId,
        'p_expected_version': expectedVersion,
      },
    );
  }

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
