import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/customer_statement.dart';

class SupabaseStatementExportRepository implements StatementExportRepository {
  SupabaseStatementExportRepository(this.client);
  final SupabaseClient client;
  @override
  Future<CustomerStatement> export(
    String requestId,
    String organizationId,
    String customerId,
    String from,
    String to,
  ) async {
    final result = await client.rpc(
      'create_customer_statement_export',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_customer_id': customerId,
        'p_from': from,
        'p_to': to,
      },
    );
    return CustomerStatement(Map<String, dynamic>.from(result as Map));
  }
}
