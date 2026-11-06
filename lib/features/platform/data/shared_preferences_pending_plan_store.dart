import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/pending_plan_draft.dart';

class SharedPreferencesPendingPlanStore implements PendingPlanDraftStore {
  String key(String actor) {
    if (actor.isEmpty) throw StateError('Missing administrator identity');
    return 'pending_plan_v1:$actor';
  }

  @override
  Future<PendingPlanDraft?> load(String actorId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key(actorId));
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown draft version');
    }
    return PendingPlanDraft(
      json['request_id'] as String,
      Map<String, dynamic>.from(json['data'] as Map),
    );
  }

  @override
  Future<void> save(String actorId, PendingPlanDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key(actorId),
      jsonEncode({
        'version': 1,
        'request_id': draft.requestId,
        'data': draft.data,
      }),
    )) {
      throw StateError('Unable to preserve draft');
    }
  }

  @override
  Future<void> clear(String actorId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(key(actorId))) {
      throw StateError('Unable to clear draft');
    }
  }
}
