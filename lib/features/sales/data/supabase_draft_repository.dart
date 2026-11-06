import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/draft_repository.dart';

class SupabaseDraftRepository implements DraftRepository {
  @override
  Future<void> checkout(
    String requestId,
    String organizationId,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String dueDate,
    List<Map<String, String>> tenders,
  ) async {
    await client.rpc(
      'checkout_sale',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_draft_id': draft.values['id'],
        'p_version': draft.values['version'],
        'p_expected_quote': quote,
        'p_due_date': dueDate,
        'p_tenders': tenders,
      },
    );
  }

  SupabaseDraftRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<SaleOption>> options(String organizationId, String type) async {
    final result = <SaleOption>[];
    if (!['customers', 'products', 'outlets'].contains(type)) {
      throw ArgumentError('Invalid option');
    }
    for (var offset = 0; ; offset += 50) {
      final List<dynamic> rows;
      if (type == 'customers') {
        rows = await client.rpc(
          'sales_customer_choices',
          params: {
            'p_organization_id': organizationId,
            'p_query': '',
            'p_offset': offset,
          },
        );
      } else {
        rows = await client
            .from(type)
            .select(type == 'products' ? 'id,name,barcode,sku' : 'id,name')
            .eq('organization_id', organizationId)
            .eq('active', true)
            .order('name')
            .order('id')
            .range(offset, offset + 49);
      }
      result.addAll(
        rows.map(
          (r) => SaleOption(
            r['id'] as String,
            r['name'] as String,
            barcode: r['barcode'] as String?,
            sku: r['sku'] as String?,
          ),
        ),
      );
      if (rows.length < 50) return result;
    }
  }

  @override
  Future<List<SaleDraft>> drafts(String organizationId, int offset) async {
    final rows = await client
        .from('sales_drafts')
        .select()
        .eq('organization_id', organizationId)
        .eq('status', 'draft')
        .order('updated_at', ascending: false)
        .order('id')
        .range(offset, offset + 49);
    return rows.map(SaleDraft.new).toList();
  }

  @override
  Future<SaleDraft> save(
    String requestId,
    String organizationId,
    SaleDraft? previous,
    String outletId,
    String? customerId,
    String state,
    List<Map<String, String>> items,
    String notes,
  ) async {
    final row = await client.rpc(
      'save_sales_draft',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_draft_id': previous?.values['id'],
        'p_version': previous?.values['version'],
        'p_outlet_id': outletId,
        'p_customer_id': customerId,
        'p_place_of_supply': state,
        'p_items': items,
        'p_notes': notes,
      },
    );
    return SaleDraft(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<Map<String, dynamic>> quote(
    String organizationId,
    SaleDraft draft,
  ) async {
    final row = await client.rpc(
      'quote_sales_draft',
      params: {
        'p_organization_id': organizationId,
        'p_draft_id': draft.values['id'],
        'p_version': draft.values['version'],
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  @override
  Future<void> issue(
    String requestId,
    String organizationId,
    SaleDraft draft,
    Map<String, dynamic> quote,
    String dueDate,
  ) async {
    await client.rpc(
      'issue_sales_invoice',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_draft_id': draft.values['id'],
        'p_version': draft.values['version'],
        'p_expected_quote': quote,
        'p_due_date': dueDate,
      },
    );
  }
}
