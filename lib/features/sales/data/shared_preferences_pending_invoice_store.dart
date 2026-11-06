import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/pending_invoice_issue.dart';

class SharedPreferencesPendingInvoiceStore implements PendingInvoiceStore {
  String prefix(String actor, String org) {
    if (actor.isEmpty || org.isEmpty) throw StateError('Missing invoice scope');
    return 'pending_invoice_issue_v1:${Uri.encodeComponent(actor)}:${Uri.encodeComponent(org)}:';
  }

  String key(String actor, PendingInvoiceIssue command) {
    final id = command.draft.values['id'] as String;
    if (id.isEmpty || command.requestId.isEmpty) {
      throw const FormatException('Invalid invoice command');
    }
    return '${prefix(actor, command.organizationId)}${Uri.encodeComponent(id)}';
  }

  @override
  Future<List<PendingInvoiceIssue>> list(
    String actorId,
    String organizationId,
  ) async {
    final scope = prefix(actorId, organizationId);
    final prefs = await SharedPreferences.getInstance();
    final commands = <PendingInvoiceIssue>[];
    for (final storedKey in prefs.getKeys().where(
      (value) => value.startsWith(scope),
    )) {
      final command = PendingInvoiceIssue.fromJson(
        jsonDecode(prefs.getString(storedKey)!) as Map<String, dynamic>,
      );
      if (command.organizationId != organizationId ||
          key(actorId, command) != storedKey) {
        throw const FormatException('Invoice command scope mismatch');
      }
      commands.add(command);
    }
    return commands;
  }

  @override
  Future<void> save(String actorId, PendingInvoiceIssue command) async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = key(actorId, command);
    final payload = jsonEncode(command.toJson());
    final existing = prefs.getString(storedKey);
    if (existing != null && existing != payload) {
      throw StateError('A different invoice confirmation is already pending');
    }
    if (!await prefs.setString(storedKey, payload)) {
      throw StateError('Unable to preserve invoice command');
    }
  }

  @override
  Future<void> clear(String actorId, PendingInvoiceIssue command) async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = key(actorId, command);
    final raw = prefs.getString(storedKey);
    if (raw == null) return;
    final stored = PendingInvoiceIssue.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    if (stored.requestId != command.requestId) {
      throw StateError('Pending invoice changed');
    }
    if (!await prefs.remove(storedKey)) {
      throw StateError('Unable to clear invoice command');
    }
  }
}
