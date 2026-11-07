import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/report_repository.dart';

class SupabaseReportRepository implements ReportRepository {
  @override
  Future<FinancialReport> exportStockValuation(
    String requestId,
    String organizationId,
  ) async {
    final result = await client.rpc(
      'create_stock_valuation_export',
      params: {'p_request_id': requestId, 'p_organization_id': organizationId},
    );
    return FinancialReport(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<FinancialReport> stockValuation(
    String organizationId,
    int offset,
  ) async {
    final result = await client.rpc(
      'stock_valuation',
      params: {'p_organization_id': organizationId, 'p_offset': offset},
    );
    return FinancialReport(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<FinancialReport> exportCustomerAging(
    String requestId,
    String organizationId,
  ) async {
    final result = await client.rpc(
      'create_customer_aging_export',
      params: {'p_request_id': requestId, 'p_organization_id': organizationId},
    );
    return FinancialReport(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<FinancialReport> customerAging(
    String organizationId,
    int offset,
  ) async {
    final result = await client.rpc(
      'customer_aging',
      params: {'p_organization_id': organizationId, 'p_offset': offset},
    );
    return FinancialReport(Map<String, dynamic>.from(result as Map));
  }

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
