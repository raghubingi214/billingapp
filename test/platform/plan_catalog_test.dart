import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/platform/domain/platform_plan_repository.dart';
import 'package:smart_billing/features/platform/presentation/platform_plans_screen.dart';
import 'package:smart_billing/features/platform/data/suggested_plan_templates.dart';
import 'package:smart_billing/features/platform/domain/pending_plan_draft.dart';

class _PendingStore implements PendingPlanDraftStore {
  bool failLoad = true, failSave = true;
  int clears = 0;
  PendingPlanDraft? pending = const PendingPlanDraft('original-command', {
    'code': 'starter_month',
    'name': 'Starter',
    'price_inr': '199',
    'monthly_invoice_limit': '1000',
    'staff_limit': '2',
    'location_limit': '1',
    'monthly_reminder_limit': '0',
    'trial_invoice_limit': null,
    'billing_interval': 'month',
    'report_types': ['sales', 'purchases', 'payments'],
  });
  @override
  Future<PendingPlanDraft?> load(String actorId) async {
    if (failLoad) throw StateError('Storage unavailable');
    return pending;
  }

  @override
  Future<void> save(String actorId, PendingPlanDraft draft) async {
    if (failSave) throw StateError('Storage unavailable');
    pending = draft;
  }

  @override
  Future<void> clear(String actorId) async {
    clears++;
    pending = null;
  }
}

class _Plans implements PlatformPlanRepository {
  int drafts = 0;
  bool failSave = false;
  final keys = <String>[];
  final payloads = <Map<String, dynamic>>[];
  @override
  Future<void> createDraft(String requestId, Map<String, dynamic> data) async {
    drafts++;
    keys.add(requestId);
    payloads.add(Map<String, dynamic>.from(data));
    if (failSave) throw StateError('Response lost');
  }

  @override
  Future<List<Map<String, dynamic>>> page(int offset) async => [
    {
      'name': 'Starter draft',
      'active': false,
      'price_inr': 199,
      'billing_interval': 'month',
      'monthly_invoice_limit': 1000,
      'staff_limit': 2,
      'location_limit': 1,
    },
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('recovery retries storage and saves locally before sending', (
    tester,
  ) async {
    final store = _PendingStore();
    final plans = _Plans();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingPlanDraftStoreProvider.overrideWithValue(store),
          platformPlanRepositoryProvider.overrideWithValue(plans),
          suggestedPlanTemplatesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: PlatformPlanDraftScreen(userId: 'admin'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(plans.drafts, 0);
    store.failLoad = false;
    await tester.tap(find.text('Retry draft recovery'));
    await tester.pumpAndSettle();
    expect(find.text('starter_month'), findsOneWidget);
    await tester.ensureVisible(find.text('Save inactive draft'));
    await tester.tap(find.text('Save inactive draft'));
    await tester.pumpAndSettle();
    expect(plans.drafts, 0);
    expect(store.clears, 0);
    store.failSave = false;
    await tester.tap(find.text('Save inactive draft'));
    await tester.pumpAndSettle();
    expect(plans.keys, ['original-command']);
    expect(store.clears, 1);
    expect(store.pending, isNull);
  });
  testWidgets('valid draft retry preserves command and explicit limits', (
    tester,
  ) async {
    final plans = _Plans()..failSave = true;
    final templates = await tester.runAsync(
      () => SuggestedPlanTemplates().load(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformPlanRepositoryProvider.overrideWithValue(plans),
          suggestedPlanTemplatesProvider.overrideWith(
            (ref) async => templates!,
          ),
        ],
        child: const MaterialApp(
          home: PlatformPlanDraftScreen(userId: 'admin'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business Annual').last);
    await tester.pumpAndSettle();
    final reminders = find.widgetWithText(TextFormField, 'Reminders per month');
    await tester.ensureVisible(reminders);
    await tester.enterText(reminders, '0');
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.ensureVisible(find.text('Save inactive draft'));
      await tester.tap(find.text('Save inactive draft'));
      await tester.pumpAndSettle();
      if (attempt == 0) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              platformPlanRepositoryProvider.overrideWithValue(plans),
              suggestedPlanTemplatesProvider.overrideWith(
                (ref) async => templates!,
              ),
            ],
            child: const MaterialApp(
              home: PlatformPlanDraftScreen(userId: 'admin'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('business_year'), findsOneWidget);
      }
    }
    expect(plans.keys.length, 2);
    expect(plans.keys.first, plans.keys.last);
    expect(plans.payloads.first, plans.payloads.last);
    expect(plans.payloads.first['price_inr'], '3999');
    expect(plans.payloads.first['billing_interval'], 'year');
    expect(plans.payloads.first['monthly_reminder_limit'], '0');
    expect(plans.payloads.first['trial_invoice_limit'], isNull);
    expect(plans.payloads.first.containsKey('active'), isFalse);
  });
  testWidgets('suggested annual template fills draft without saving', (
    tester,
  ) async {
    final plans = _Plans();
    final templates = await tester.runAsync(
      () => SuggestedPlanTemplates().load(),
    );
    expect(templates, isNotEmpty);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformPlanRepositoryProvider.overrideWithValue(plans),
          suggestedPlanTemplatesProvider.overrideWith(
            (ref) async => templates!,
          ),
        ],
        child: const MaterialApp(
          home: PlatformPlanDraftScreen(userId: 'admin'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business Annual').last);
    await tester.pumpAndSettle();
    expect(find.text('business_year'), findsOneWidget);
    expect(find.text('3999'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'year',
    );
    expect(plans.drafts, 0);
  });
  testWidgets('invalid draft never reaches backend', (tester) async {
    final plans = _Plans();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformPlanRepositoryProvider.overrideWithValue(plans),
          suggestedPlanTemplatesProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: PlatformPlanDraftScreen(userId: 'admin'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save inactive draft'));
    await tester.tap(find.text('Save inactive draft'));
    await tester.pumpAndSettle();
    expect(plans.drafts, 0);
    expect(find.text('Enter a name up to 120 characters'), findsOneWidget);
  });
  testWidgets('plan catalog labels drafts without activation actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformPlanRepositoryProvider.overrideWithValue(_Plans())],
        child: const MaterialApp(home: PlatformPlansScreen(userId: 'admin')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Starter draft'), findsOneWidget);
    expect(find.text('Inactive draft · ₹199 / month'), findsOneWidget);
    expect(find.text('Activate'), findsNothing);
    await tester.tap(find.text('Starter draft'));
    await tester.pumpAndSettle();
    expect(find.text('Users including owner'), findsOneWidget);
  });
}
