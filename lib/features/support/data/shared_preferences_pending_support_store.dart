import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/pending_support_request.dart';

class SharedPreferencesPendingSupportStore implements PendingSupportStore {
  String _key(String actor, String org) => 'pending_support_v1:$actor:$org';
  @override
  Future<void> save(String actor, PendingSupportRequest request) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _key(actor, request.organizationId),
      jsonEncode(request.toJson()),
    )) {
      throw StateError('Unable to save request');
    }
  }

  @override
  Future<PendingSupportRequest?> load(
    String actor,
    String organizationId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(actor, organizationId));
    if (raw == null) return null;
    final request = PendingSupportRequest.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (request.organizationId != organizationId) {
      throw const FormatException('Request scope mismatch');
    }
    return request;
  }

  @override
  Future<void> clear(String actor, String organizationId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key(actor, organizationId))) {
      throw StateError('Unable to clear request');
    }
  }
}
