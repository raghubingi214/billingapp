import 'dart:typed_data';

class ProductImageRejected implements Exception {
  const ProductImageRejected();
}

abstract interface class CatalogImageRepository {
  Future<void> upload(String path, Uint8List jpeg);
  Future<void> attach(
    String requestId,
    String organizationId,
    String productId,
    int version,
    String? path,
  );
  Future<String> signedUrl(String path);
}
