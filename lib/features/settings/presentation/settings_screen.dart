import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/settings_repository.dart';
import '../data/supabase_settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SupabaseSettingsRepository(ref.watch(supabaseClientProvider)),
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    required this.organizationId,
    required this.onSaved,
  });
  final String organizationId;
  final VoidCallback onSaved;
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'name',
      'legal_name',
      'state_code',
      'gstin',
      'line1',
      'city',
      'postal_code',
      'prefix',
    ])
      key: TextEditingController(),
  };
  int version = 0;
  String regime = 'unregistered',
      requestId = const Uuid().v4(),
      lastPayload = '';
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final settings = await ref
          .read(settingsRepositoryProvider)
          .load(widget.organizationId);
      if (!mounted) return;
      final address = settings.values['address'] as Map;
      for (final key in fields.keys) {
        fields[key]!.text =
            (['line1', 'city', 'postal_code'].contains(key)
                    ? address[key]
                    : settings.values[key])
                ?.toString() ??
            '';
      }
      setState(() {
        version = settings.version;
        regime = settings.values['tax_regime'] as String;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to load settings. Check access and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update business settings?'),
        content: const Text(
          'Changes apply to future invoices. Issued invoices retain their original details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save settings'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final values = <String, Object?>{
      for (final key in ['name', 'legal_name', 'state_code', 'gstin', 'prefix'])
        key: fields[key]!.text.trim(),
      'tax_regime': regime,
      'address': {
        for (final key in ['line1', 'city', 'postal_code'])
          key: fields[key]!.text.trim(),
      },
    };
    final payload = '$version|$values';
    if (lastPayload != payload) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .save(requestId, widget.organizationId, version, values);
      if (mounted) {
        widget.onSaved();
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save settings. Check details and permissions. Reopen if settings changed elsewhere.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business settings')),
    body: SafeArea(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: TextButton(onPressed: load, child: Text(error!)),
            )
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: regime,
                    decoration: const InputDecoration(labelText: 'Tax regime'),
                    items:
                        [
                              ('unregistered', 'Unregistered'),
                              ('regular', 'Regular GST'),
                              ('composition', 'Composition'),
                            ]
                            .map(
                              (option) => DropdownMenuItem(
                                value: option.$1,
                                child: Text(option.$2),
                              ),
                            )
                            .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => regime = value!),
                  ),
                  const SizedBox(height: 16),
                  for (final entry in fields.entries) ...[
                    TextFormField(
                      controller: entry.value,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: {
                          'name': 'Business name',
                          'legal_name': 'Legal name',
                          'state_code': 'State code',
                          'gstin': 'GSTIN',
                          'line1': 'Street address',
                          'city': 'City',
                          'postal_code': 'Postal code',
                          'prefix': 'Invoice prefix',
                        }[entry.key],
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (entry.key == 'gstin') {
                          if (regime == 'unregistered') {
                            return text.isEmpty
                                ? null
                                : 'Clear GSTIN for an unregistered business';
                          }
                          return RegExp(
                                    r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                                  ).hasMatch(text.toUpperCase()) &&
                                  text.startsWith(
                                    fields['state_code']!.text.trim(),
                                  )
                              ? null
                              : 'Enter GSTIN matching the state';
                        }
                        if (text.isEmpty) return 'Required';
                        if (entry.key == 'state_code' &&
                            (!RegExp(r'^\d{2}$').hasMatch(text) ||
                                (int.tryParse(text) ?? 0) < 1 ||
                                (int.tryParse(text) ?? 99) > 38)) {
                          return 'Use a valid 2-digit state code';
                        }
                        if (entry.key == 'postal_code' &&
                            !RegExp(r'^[1-9]\d{5}$').hasMatch(text)) {
                          return 'Use a 6-digit postal code';
                        }
                        if (entry.key == 'prefix' &&
                            !RegExp(r'^[A-Z0-9]{1,4}$').hasMatch(text)) {
                          return 'Use 1–4 uppercase letters or digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(busy ? 'Saving…' : 'Review settings'),
                  ),
                ],
              ),
            ),
    ),
  );
}
