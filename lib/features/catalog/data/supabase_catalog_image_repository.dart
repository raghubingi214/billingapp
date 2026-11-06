import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/catalog_image_repository.dart';

class SupabaseCatalogImageRepository implements CatalogImageRepository {
  SupabaseCatalogImageRepository(this.client);
  final SupabaseClient client;
  @override
  Future<void> upload(String path, Uint8List jpeg) async {
    try {
      await client.storage
          .from('catalog-images')
          .uploadBinary(
            path,
            jpeg,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
    } catch (_) {
      // A lost response can leave the immutable object already uploaded.
      // Confirm its exact contents before continuing to the attachment command.
      try {
        final stored = await client.storage
            .from('catalog-images')
            .download(path);
        if (stored.length == jpeg.length) {
          var matches = true;
          for (var i = 0; i < jpeg.length; i++) {
            if (stored[i] != jpeg[i]) {
              matches = false;
              break;
            }
          }
          if (matches) return;
        }
      } catch (_) {
        // Keep the original upload failure when verification is unavailable.
      }
      rethrow;
    }
  }

  @override
  Future<void> attach(
    String requestId,
    String organizationId,
    String productId,
    int version,
    String? path,
  ) async {
    await client.rpc(
      'set_product_image',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_product_id': productId,
        'p_version': version,
        'p_path': path,
      },
    );
  }

  @override
  Future<String> signedUrl(String path) =>
      client.storage.from('catalog-images').createSignedUrl(path, 300);
}
