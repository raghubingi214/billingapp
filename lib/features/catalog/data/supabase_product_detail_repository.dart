import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/catalog_repository.dart';
import '../domain/product_detail_repository.dart';

class SupabaseProductDetailRepository implements ProductDetailRepository {
  SupabaseProductDetailRepository(this.client);
  final SupabaseClient client;
  @override
  Future<CatalogProduct> load(String organizationId, String productId) async {
    final row = await client
        .from('products')
        .select(
          'id,version,name,type,sku,barcode,category,unit,hsn_sac,sale_price,purchase_price,tax_percent,price_includes_tax,reorder_level,active,image_path',
        )
        .eq('organization_id', organizationId)
        .eq('id', productId)
        .single();
    return CatalogProduct(
      id: row['id'] as String,
      version: row['version'] as int,
      name: row['name'] as String,
      type: row['type'] as String,
      values: row,
    );
  }
}
