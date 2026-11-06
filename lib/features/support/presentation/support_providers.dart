import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_support_repository.dart';
import '../data/shared_preferences_pending_support_store.dart';
import '../domain/support_repository.dart';
import '../domain/pending_support_request.dart';

final pendingSupportStoreProvider = Provider<PendingSupportStore>(
  (ref) => SharedPreferencesPendingSupportStore(),
);

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupabaseSupportRepository(ref.watch(supabaseClientProvider)),
);
final supportHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String organizationId, int offset})>(
      (ref, page) => ref
          .watch(supportRepositoryProvider)
          .history(page.organizationId, page.offset),
    );
