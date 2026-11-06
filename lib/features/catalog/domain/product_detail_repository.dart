import 'catalog_repository.dart';

abstract interface class ProductDetailRepository {
  Future<CatalogProduct> load(String organizationId, String productId);
}
