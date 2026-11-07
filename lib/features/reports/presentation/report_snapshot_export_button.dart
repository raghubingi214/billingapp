import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/sharing/share_csv.dart';
import '../domain/report_repository.dart';

final reportSnapshotShareProvider = Provider((ref) => shareCsv);

class ReportSnapshotExportButton extends ConsumerStatefulWidget {
  const ReportSnapshotExportButton({
    super.key,
    required this.filenamePrefix,
    required this.load,
    required this.encode,
    required this.enabled,
  });

  final String filenamePrefix;
  final Future<FinancialReport> Function(String requestId) load;
  final String Function(FinancialReport report) encode;
  final bool enabled;

  @override
  ConsumerState<ReportSnapshotExportButton> createState() =>
      _ReportSnapshotExportButtonState();
}

class _ReportSnapshotExportButtonState
    extends ConsumerState<ReportSnapshotExportButton> {
  bool busy = false;
  String? requestId;

  Future<void> export() async {
    if (busy) return;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final report = await widget.load(requestId ??= const Uuid().v4());
      if (!mounted) return;
      await ref.read(reportSnapshotShareProvider)(
        widget.encode(report),
        '${widget.filenamePrefix}-${report.values['as_of']}.csv',
        origin,
      );
      requestId = null;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not export this report. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: busy || !widget.enabled ? null : export,
    icon: const Icon(Icons.share_outlined),
    label: Text(busy ? 'Exporting…' : 'Export full CSV'),
  );
}
