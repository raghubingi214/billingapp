class PendingPlanDraft {
  const PendingPlanDraft(this.requestId, this.data);
  final String requestId;
  final Map<String, dynamic> data;
}

abstract interface class PendingPlanDraftStore {
  Future<PendingPlanDraft?> load(String actorId);
  Future<void> save(String actorId, PendingPlanDraft draft);
  Future<void> clear(String actorId);
}
