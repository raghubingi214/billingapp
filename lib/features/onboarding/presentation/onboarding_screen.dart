import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/business_draft.dart';
import 'onboarding_providers.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({
    super.key,
    required this.userId,
    required this.onCompleted,
  });
  final String userId;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(onboardingControllerProvider(userId))
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('Business setup')),
          body: Center(
            child: FilledButton(
              onPressed: () =>
                  ref.invalidate(onboardingControllerProvider(userId)),
              child: const Text('Retry setup'),
            ),
          ),
        ),
        data: (state) => _BusinessForm(
          key: ValueKey(userId),
          userId: userId,
          state: state,
          onCompleted: onCompleted,
        ),
      );
}

class _BusinessForm extends ConsumerStatefulWidget {
  const _BusinessForm({
    super.key,
    required this.userId,
    required this.state,
    required this.onCompleted,
  });
  final String userId;
  final OnboardingState state;
  final VoidCallback onCompleted;
  @override
  ConsumerState<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends ConsumerState<_BusinessForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name,
      legalName,
      line1,
      city,
      postalCode,
      gstin,
      prefix;
  late String stateCode;
  late TaxRegime regime;

  @override
  void initState() {
    super.initState();
    final draft = widget.state.draft;
    name = TextEditingController(text: draft.name);
    legalName = TextEditingController(text: draft.legalName);
    line1 = TextEditingController(text: draft.line1);
    city = TextEditingController(text: draft.city);
    postalCode = TextEditingController(text: draft.postalCode);
    gstin = TextEditingController(text: draft.gstin);
    prefix = TextEditingController(text: draft.prefix);
    stateCode = draft.stateCode;
    regime = draft.taxRegime;
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      legalName,
      line1,
      city,
      postalCode,
      gstin,
      prefix,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  BusinessDraft get draft => widget.state.draft.copyWith(
    name: name.text,
    legalName: legalName.text,
    line1: line1.text,
    city: city.text,
    postalCode: postalCode.text,
    stateCode: stateCode,
    taxRegime: regime,
    gstin: gstin.text.toUpperCase(),
    prefix: prefix.text.toUpperCase(),
  );

  OnboardingController get controller =>
      ref.read(onboardingControllerProvider(widget.userId).notifier);
  bool get locked => widget.state.busy || widget.state.draft.submitted;

  Future<void> next() async {
    if (!formKey.currentState!.validate()) return;
    await controller.save(draft.copyWith(step: widget.state.draft.step + 1));
  }

  Future<void> finish() async {
    final done = await controller.submit();
    if (done && mounted) widget.onCompleted();
  }

  Future<void> saveProgress() async {
    final saved = await controller.save(draft);
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress saved on this device.')),
      );
    }
  }

  Widget field(
    String label,
    TextEditingController text,
    String key, {
    TextInputType? type,
    int lines = 1,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: text,
      enabled: !locked,
      keyboardType: type,
      maxLines: lines,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
      ),
      textCapitalization: key == 'gstin' || key == 'prefix'
          ? TextCapitalization.characters
          : TextCapitalization.words,
      inputFormatters: type == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      validator: (_) => draft.validate()[key],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final current = widget.state;
    final step = current.draft.step;
    return PopScope(
      canPop: !current.busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Set up your business')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Semantics(
                      label: 'Step ${step + 1} of 3',
                      child: LinearProgressIndicator(
                        value: (step + 1) / 3,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      [
                        '1  Profile',
                        '2  Tax & invoices',
                        '3  Review & finish',
                      ][step],
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      [
                        'Tell us about your shop',
                        'Choose your tax setup',
                        'Ready for your first sale',
                      ][step],
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        'These details identify your business on invoices.',
                        'Choose the registration that applies to your business.',
                        'Check these details before creating your business.',
                      ][step],
                    ),
                    const SizedBox(height: 24),
                    if (step == 0) ...[
                      field(
                        'Shop / business name',
                        name,
                        'name',
                        maxLength: 120,
                      ),
                      field(
                        'Legal business name',
                        legalName,
                        'legalName',
                        maxLength: 160,
                      ),
                      field(
                        'Business address',
                        line1,
                        'line1',
                        lines: 2,
                        maxLength: 300,
                      ),
                      field('City', city, 'city', maxLength: 100),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          initialValue: stateCode.isEmpty ? null : stateCode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'State / territory',
                          ),
                          items: _states.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                          onChanged: locked
                              ? null
                              : (value) =>
                                    setState(() => stateCode = value ?? ''),
                          validator: (_) =>
                              draft.validateProfile()['stateCode'],
                        ),
                      ),
                      field(
                        'PIN code',
                        postalCode,
                        'postalCode',
                        type: TextInputType.number,
                        maxLength: 6,
                      ),
                    ],
                    if (step == 1) ...[
                      ...TaxRegime.values.map(
                        (taxRegime) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            color: regime == taxRegime
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: locked
                                  ? null
                                  : () => setState(() => regime = taxRegime),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      regime == taxRegime
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      semanticLabel: regime == taxRegime
                                          ? 'Selected'
                                          : 'Not selected',
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            taxRegime.label,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(taxRegime.description),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (regime != TaxRegime.unregistered)
                        field('GSTIN', gstin, 'gstin', maxLength: 15),
                      field('Invoice prefix', prefix, 'prefix', maxLength: 4),
                      const Text(
                        'The first outlet uses INR and India time. Invoice numbers will be assigned when a sale is issued.',
                      ),
                    ],
                    if (step == 2) ...[
                      _ReviewCard(draft: draft),
                      const SizedBox(height: 16),
                      if (current.draft.submitted &&
                          current.organizationId == null)
                        const Text(
                          'Setup has been submitted. Retry to finish the same request safely.',
                        ),
                    ],
                    if (current.message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            current.message!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: current.busy
                          ? null
                          : step == 2
                          ? finish
                          : next,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          current.busy
                              ? 'Saving…'
                              : step == 2
                              ? (current.draft.submitted
                                    ? 'Retry setup'
                                    : 'Create business')
                              : 'Continue',
                        ),
                      ),
                    ),
                    if (step > 0 && !current.draft.submitted)
                      TextButton(
                        onPressed: current.busy
                            ? null
                            : () => controller.save(
                                draft.copyWith(step: step - 1),
                              ),
                        child: const Text('Back'),
                      ),
                    if (!current.draft.submitted)
                      TextButton(
                        onPressed: current.busy ? null : saveProgress,
                        child: const Text('Save progress'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.draft});
  final BusinessDraft draft;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.storefront_outlined, size: 36),
          const SizedBox(height: 16),
          Text(draft.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(draft.legalName),
          const SizedBox(height: 16),
          Text(draft.line1),
          Text(
            '${draft.city}, ${_states[draft.stateCode]} ${draft.postalCode}',
          ),
          const Divider(height: 32),
          Text('Tax registration: ${draft.taxRegime.label}'),
          if (draft.taxRegime != TaxRegime.unregistered)
            Text('GSTIN: ${draft.gstin}'),
          const SizedBox(height: 8),
          Text('Invoice prefix: ${draft.prefix}'),
          const SizedBox(height: 8),
          const Text('Currency: INR  •  Time zone: India'),
        ],
      ),
    ),
  );
}

const _states = {
  '01': 'Jammu and Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '26': 'Dadra and Nagar Haveli and Daman and Diu',
  '27': 'Maharashtra',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman and Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
};
