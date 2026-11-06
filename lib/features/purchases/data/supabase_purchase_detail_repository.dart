import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/purchase_detail_repository.dart';

class SupabasePurchaseDetailRepository implements PurchaseDetailRepository {
  SupabasePurchaseDetailRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> recordSupplierCreditRefund(
    String requestId,
    String organizationId,
    String purchaseId,
    String amount,
    String date,
    String method,
    String? reference,
  ) async {
    await client.rpc(
      'record_supplier_credit_refund',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_purchase_id': purchaseId,
        'p_amount': amount,
        'p_date': date,
        'p_method': method,
        'p_reference': reference,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> previewReturn(
    String organizationId,
    String purchaseId,
    List<Map<String, String>> items,
  ) async {
    final result = await client.rpc(
      'preview_purchase_return',
      params: {
        'p_organization_id': organizationId,
        'p_purchase_id': purchaseId,
        'p_items': items,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> returnPurchase(
    String requestId,
    String organizationId,
    String purchaseId,
    String reason,
    String? reference,
    List<Map<String, String>> items,
  ) async {
    await client.rpc(
      'return_purchase',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_purchase_id': purchaseId,
        'p_reason': reason,
        'p_credit_reference': reference,
        'p_items': items,
      },
    );
  }

  @override
  Future<PurchaseDetail> detail(
    String organizationId,
    String purchaseId,
  ) async {
    final result = await client.rpc(
      'purchase_detail',
      params: {
        'p_organization_id': organizationId,
        'p_purchase_id': purchaseId,
      },
    );
    if (result == null) throw StateError('Purchase unavailable');
    return PurchaseDetail(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> pay(
    String requestId,
    String organizationId,
    String supplierId,
    String purchaseId,
    String amount,
    String method,
    String reference,
    String date,
  ) async {
    await client.rpc(
      'pay_supplier',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_supplier_id': supplierId,
        'p_date': date,
        'p_method': method,
        'p_reference': reference,
        'p_allocations': [
          {'purchase_id': purchaseId, 'amount': amount},
        ],
      },
    );
  }
}
