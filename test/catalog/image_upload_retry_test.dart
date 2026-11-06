import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_billing/features/catalog/data/supabase_catalog_image_repository.dart';

void main() {
  for (final matches in [true, false]) {
    test(
      'lost upload response ${matches ? 'accepts matching' : 'rejects different'} stored bytes',
      () async {
        final transport = MockClient((request) async {
          if (request.method == 'POST') {
            throw http.ClientException('Response lost');
          }
          return http.Response.bytes(matches ? [1, 2, 3] : [1, 2, 4], 200);
        });
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          httpClient: transport,
        );
        addTearDown(client.dispose);
        final repository = SupabaseCatalogImageRepository(client);
        final operation = repository.upload(
          'org/product/asset.jpg',
          Uint8List.fromList([1, 2, 3]),
        );
        if (matches) {
          await operation;
        } else {
          await expectLater(operation, throwsA(isA<Exception>()));
        }
      },
    );
  }
}
