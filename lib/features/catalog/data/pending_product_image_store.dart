import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef ProductImageCommand = ({String requestId, int version, String? path});

class PendingProductImageStore {
  PendingProductImageStore(String actor, String organization, String product)
    : _key = [
        'pending_product_image_v1',
        actor,
        organization,
        product,
      ].map(Uri.encodeComponent).join(':');

  final String _key;

  Future<ProductImageCommand?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (
      requestId: data['request_id'] as String,
      version: data['version'] as int,
      path: data['path'] as String?,
    );
  }

  Future<void> save(ProductImageCommand command) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'request_id': command.requestId,
      'version': command.version,
      'path': command.path,
    });
    final existing = prefs.getString(_key);
    if (existing != null && existing != payload) {
      throw StateError('Another image change is awaiting confirmation');
    }
    if (!await prefs.setString(_key, payload)) {
      throw StateError('Unable to preserve image change');
    }
  }

  Future<void> clear(ProductImageCommand command) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['request_id'] != command.requestId || !await prefs.remove(_key)) {
      throw StateError('Unable to clear image change');
    }
  }
}
