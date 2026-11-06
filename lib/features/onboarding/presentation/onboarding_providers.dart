import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../../../shared/domain/membership.dart';
import '../data/supabase_organization_repository.dart';
import '../domain/business_draft.dart';
import '../domain/create_organization.dart';
import '../domain/organization_repository.dart';

final organizationRepositoryProvider = Provider<OrganizationRepository>(
  (ref) => SupabaseOrganizationRepository(ref.watch(supabaseClientProvider)),
);

final membershipProvider = FutureProvider.autoDispose
    .family<List<Membership>, String>(
      (ref, userId) =>
          ref.watch(organizationRepositoryProvider).memberships(userId),
    );

final activeOrganizationProvider =
    NotifierProvider.family<ActiveOrganization, Membership?, String>(
      ActiveOrganization.new,
    );

class ActiveOrganization extends Notifier<Membership?> {
  ActiveOrganization(this.userId);
  final String userId;
  @override
  Membership? build() => null;
  void select(Membership membership) => state = membership;
  void clear() => state = null;
}

class OnboardingState {
  const OnboardingState(
    this.draft, {
    this.busy = false,
    this.message,
    this.organizationId,
  });
  final BusinessDraft draft;
  final bool busy;
  final String? message, organizationId;
}

final onboardingControllerProvider = AsyncNotifierProvider.autoDispose
    .family<OnboardingController, OnboardingState, String>(
      OnboardingController.new,
    );

class OnboardingController extends AsyncNotifier<OnboardingState> {
  OnboardingController(this.userId);
  final String userId;
  OrganizationRepository get _repository =>
      ref.read(organizationRepositoryProvider);

  @override
  Future<OnboardingState> build() async {
    final saved = await _repository.loadDraft(userId);
    return OnboardingState(
      saved ?? BusinessDraft(requestId: const Uuid().v4()),
    );
  }

  Future<bool> save(BusinessDraft draft) async {
    final current = state.asData?.value;
    if (current == null || current.busy || current.draft.submitted) {
      return false;
    }
    final prepared = draft.copyWith(
      requestId: current.draft.fingerprint == draft.fingerprint
          ? current.draft.requestId
          : const Uuid().v4(),
    );
    state = AsyncData(OnboardingState(prepared, busy: true));
    try {
      await _repository.saveDraft(userId, prepared);
      if (ref.mounted) state = AsyncData(OnboardingState(prepared));
      return true;
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          OnboardingState(
            prepared,
            message: 'Unable to save your progress. Please try again.',
          ),
        );
      }
      return false;
    }
  }

  Future<bool> submit() async {
    final current = state.asData?.value;
    if (current == null || current.busy) return false;
    final draft = current.draft.copyWith(submitted: true, step: 2);
    final validation = draft.validate();
    if (validation.isNotEmpty) {
      state = AsyncData(
        OnboardingState(current.draft, message: validation.values.first),
      );
      return false;
    }
    state = AsyncData(OnboardingState(draft, busy: true));
    try {
      // Persist the command key before the network request. A lost response is
      // retried with exactly the same payload, including after an app restart.
      await _repository.saveDraft(userId, draft);
      final organizationId = await CreateOrganization(_repository)(draft);
      try {
        await _repository.clearDraft(userId);
      } catch (_) {
        /* Same key remains safe to retry. */
      }
      if (!ref.mounted) return true;
      ref.invalidate(membershipProvider(userId));
      state = AsyncData(OnboardingState(draft, organizationId: organizationId));
      return true;
    } on OnboardingFailure catch (error) {
      if (ref.mounted) {
        state = AsyncData(OnboardingState(draft, message: error.message));
      }
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          OnboardingState(
            draft,
            message: 'Setup did not finish. Retry to safely check the result.',
          ),
        );
      }
    }
    return false;
  }
}
