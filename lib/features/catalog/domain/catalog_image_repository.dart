import 'dart:typed_data';

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
