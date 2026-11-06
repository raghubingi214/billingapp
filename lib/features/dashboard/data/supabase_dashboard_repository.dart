import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/dashboard_repository.dart';

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository(this.client);
  final SupabaseClient client;
  @override
  Future<DashboardSummary> summary(
    String organizationId,
    String from,
    String to,
  ) async {
    final row = await client.rpc(
      'dashboard_summary',
      params: {'p_organization_id': organizationId, 'p_from': from, 'p_to': to},
    );
    return DashboardSummary(
      row['sales'].toString(),
      row['collections'].toString(),
      row['outstanding'].toString(),
      row['low_stock'] as int,
      row['refreshed_at'] as String,
      row['cashier_scope'] as bool,
    );
  }
}
