import 'package:flutter/material.dart';
import '../domain/inventory_repository.dart';

class StockHistorySheet extends StatefulWidget {
  const StockHistorySheet({
    super.key,
    required this.product,
    required this.unit,
    required this.loadPage,
  });
  final String product, unit;
  final Future<List<StockMovement>> Function(int offset) loadPage;
  @override
  State<StockHistorySheet> createState() => _StockHistorySheetState();
}

class _StockHistorySheetState extends State<StockHistorySheet> {
  List<StockMovement> rows = [];
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await widget.loadPage(rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load movement history. Retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.product,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: rows.length + 1,
              itemBuilder: (context, index) {
                if (index < rows.length) {
                  final row = rows[index];
                  final date = DateTime.tryParse(row.createdAt)?.toLocal();
                  return ListTile(
                    title: Text('${row.quantity} ${widget.unit}'),
                    subtitle: Text('${row.reason}\n${date ?? row.createdAt}'),
                  );
                }
                if (error != null) {
                  return TextButton(onPressed: load, child: Text(error!));
                }
                if (busy) return const SizedBox.shrink();
                if (rows.isEmpty) {
                  return const ListTile(title: Text('No movements yet'));
                }
                if (more) {
                  return TextButton(
                    onPressed: load,
                    child: const Text('Load older movements'),
                  );
                }
                return const ListTile(title: Text('All movements loaded'));
              },
            ),
          ),
        ],
      ),
    ),
  );
}
