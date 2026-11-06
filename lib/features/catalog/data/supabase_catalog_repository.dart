import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/catalog_repository.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<CatalogProduct>> page(
    String organizationId,
    int offset, {
    required bool archived,
    String query = '',
  }) async {
    final result = await client.rpc(
      'search_products',
      params: {
        'p_organization_id': organizationId,
        'p_query': query,
        'p_archived': archived,
        'p_offset': offset,
      },
    );
    final rows = (result as List).map(
      (row) => Map<String, dynamic>.from(row as Map),
    );
    return rows
        .map(
          (row) => CatalogProduct(
            id: row['id'] as String,
            version: row['version'] as int,
            name: row['name'] as String,
            type: row['type'] as String,
            values: row,
          ),
        )
        .toList();
  }

  @override
  Future<void> save(
    String requestId,
    String organizationId,
    CatalogProduct? previous,
    Map<String, Object?> values,
  ) async {
    await client.rpc(
      'save_product',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_product_id': previous?.id,
        'p_version': previous?.version,
        'p_data': values,
      },
    );
  }
}
