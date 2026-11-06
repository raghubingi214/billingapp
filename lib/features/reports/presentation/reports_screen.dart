import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/report_repository.dart';
import '../data/supabase_report_repository.dart';
import '../domain/report_csv.dart';
import '../../../integrations/sharing/share_csv.dart';
import 'package:uuid/uuid.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => SupabaseReportRepository(ref.watch(supabaseClientProvider)),
);

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String exportKey = const Uuid().v4(), exportFilters = '';
  Future<void> export(BuildContext anchor) async {
    if (busy || !form.currentState!.validate()) return;
    final filters = '$kind|${from.text}|${to.text}';
    if (exportFilters != filters) {
      exportKey = const Uuid().v4();
      exportFilters = filters;
    }
    final box = anchor.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final report = await ref
          .read(reportRepositoryProvider)
          .export(exportKey, widget.organizationId, kind, from.text, to.text);
      if (!mounted) return;
      await shareCsv(
        ReportCsv.encode(report),
        '$kind-${from.text}-${to.text}.csv',
        origin,
      );
      exportFilters =
          ''; // A later user-requested export captures a new snapshot.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not export report. Check access and date range, then retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final form = GlobalKey<FormState>(),
      from = TextEditingController(),
      to = TextEditingController();
  String kind = 'sales';
  Map<String, dynamic>? summary;
  List<dynamic> rows = [];
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    from.text = DateTime(
      now.year,
      now.month,
      1,
    ).toIso8601String().substring(0, 10);
    to.text = now.toIso8601String().substring(0, 10);
    load(reset: true);
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    if (form.currentState != null && !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (reset) {
        rows = [];
        summary = null;
      }
      final page = await ref
          .read(reportRepositoryProvider)
          .page(widget.organizationId, kind, from.text, to.text, rows.length);
      if (mounted) {
        setState(() {
          summary = page.values;
          final entries = page.values['rows'] as List;
          rows = [...rows, ...entries];
          more = entries.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to load report. Check dates and access.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reports')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Report'),
              items:
                  [
                        ('sales', 'Sales and credits'),
                        ('purchases', 'Purchases'),
                        ('payments', 'Cash flow'),
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
                  : (value) => setState(() {
                      kind = value!;
                      rows = [];
                      summary = null;
                      more = false;
                    }),
            ),
            const SizedBox(height: 16),
            for (final field in [(from, 'From'), (to, 'To')])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: field.$1,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: '${field.$2} (YYYY-MM-DD)',
                  ),
                  onChanged: (_) => setState(() {
                    rows = [];
                    summary = null;
                    more = false;
                  }),
                  validator: (value) =>
                      DateTime.tryParse(value ?? '') != null &&
                          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value!)
                      ? null
                      : 'Enter a valid date',
                ),
              ),
            FilledButton(
              onPressed: busy ? null : () => load(reset: true),
              child: const Text('Apply filters'),
            ),
            Builder(
              builder: (anchor) => OutlinedButton.icon(
                onPressed: busy ? null : () => export(anchor),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Export full CSV'),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (summary != null) ...[
              const SizedBox(height: 16),
              Text(
                'Total INR ${summary!['total']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${summary!['count']} posted records · ${summary!['from']} to ${summary!['to']}',
              ),
              Text(
                summary!['note'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Generated ${summary!['generated_at']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text('${row['type']} · ${row['reference']}'),
                  subtitle: Text(
                    '${row['date']}${row['tax'] != null ? ' · Tax INR ${row['tax']}' : ''}',
                  ),
                  trailing: Text('INR ${row['amount']}'),
                ),
              ),
            if (summary != null && rows.isEmpty && !busy)
              const ListTile(title: Text('No posted records for this period')),
            if (more && !busy && summary != null)
              TextButton(
                onPressed: () => load(),
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    ),
  );
}
