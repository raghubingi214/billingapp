import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/report_repository.dart';

class SupabaseReportRepository implements ReportRepository {
  @override
  Future<FinancialReport> export(
    String requestId,
    String organizationId,
    String kind,
    String from,
    String to,
  ) async {
    final result = await client.rpc(
      'create_report_export',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_kind': kind,
        'p_from': from,
        'p_to': to,
      },
    );
    return FinancialReport(Map<String, dynamic>.from(result as Map));
  }

  SupabaseReportRepository(this.client);
  final SupabaseClient client;
  @override
  Future<FinancialReport> page(
    String organizationId,
    String kind,
    String from,
    String to,
    int offset,
  ) async {
    final result = await client.rpc(
      'financial_report',
      params: {
        'p_organization_id': organizationId,
        'p_kind': kind,
        'p_from': from,
        'p_to': to,
        'p_offset': offset,
      },
    );
    return FinancialReport(Map<String, dynamic>.from(result as Map));
  }
}
