import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/catalog_repository.dart';
import '../data/supabase_catalog_repository.dart';
import 'product_editor.dart';
import 'product_image_screen.dart';
import '../../../integrations/scanning/barcode_scanner.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SupabaseCatalogRepository(ref.watch(supabaseClientProvider)),
);

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({
    super.key,
    required this.organizationId,
    required this.canManage,
  });
  final String organizationId;
  final bool canManage;
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  List<CatalogProduct> products = [];
  bool loading = false, more = true, archived = false;
  String search = '';
  String? error;
  Timer? debounce;
  final searchController = TextEditingController();
  bool reloadQueued = false;
  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (loading) {
      reloadQueued = true;
      return;
    }
    final requestedSearch = search;
    setState(() {
      loading = true;
      error = null;
      if (reset) products = [];
    });
    try {
      final page = await ref
          .read(catalogRepositoryProvider)
          .page(
            widget.organizationId,
            products.length,
            archived: archived,
            query: requestedSearch,
          );
      if (mounted && requestedSearch == search) {
        setState(() {
          products = [...products, ...page];
          more = page.length == 50;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load products. Please retry.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (reloadQueued || requestedSearch != search) {
          reloadQueued = false;
          load(reset: true);
        }
      }
    }
  }

  Future<void> edit(CatalogProduct? product) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductEditor(
          organizationId: widget.organizationId,
          product: product,
        ),
      ),
    );
    if (saved == true && mounted) load(reset: true);
  }

  Future<void> archive(CatalogProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(archived ? 'Restore product?' : 'Archive product?'),
        content: Text(product.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).save(
        const Uuid().v4(),
        widget.organizationId,
        product,
        {
          ...product.values,
          for (final key in [
            'sale_price',
            'purchase_price',
            'tax_percent',
            'reorder_level',
          ])
            key: product.values[key].toString(),
          'active': archived,
        },
      );
      if (mounted) load(reset: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save. Refresh the list and try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = products
        .where(
          (p) => [
            p.name,
            p.values['sku'],
            p.values['barcode'],
          ].join(' ').toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Products & services')),
      floatingActionButton: widget.canManage
          ? FloatingActionButton(
              tooltip: 'Add product or service',
              onPressed: () => edit(null),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => load(reset: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search products, SKU or barcode',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Scan barcode',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final value = await ref.read(barcodeScannerProvider)(
                        context,
                      );
                      if (value == null || !mounted) return;
                      debounce?.cancel();
                      searchController.text = value;
                      setState(() => search = value);
                      load(reset: true);
                    },
                  ),
                ),
                onChanged: (value) {
                  setState(() => search = value);
                  debounce?.cancel();
                  debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => load(reset: true),
                  );
                },
              ),
              SwitchListTile(
                title: const Text('Show archived'),
                value: archived,
                onChanged: loading
                    ? null
                    : (value) {
                        setState(() => archived = value);
                        load(reset: true);
                      },
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                TextButton(onPressed: () => load(), child: Text(error!)),
              if (!loading && error == null && visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching products.'),
                ),
              for (final product in visible)
                Card(
                  child: ListTile(
                    title: Text(product.name),
                    leading: IconButton(
                      tooltip: 'Product image',
                      icon: const Icon(Icons.image_outlined),
                      onPressed: () async {
                        final saved = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ProductImageScreen(
                              organizationId: widget.organizationId,
                              product: product,
                              canManage: widget.canManage,
                            ),
                          ),
                        );
                        if (saved == true && mounted) load(reset: true);
                      },
                    ),
                    subtitle: Text(
                      '${product.type} · ₹${product.values['sale_price']} / ${product.values['unit']}',
                    ),
                    onTap: widget.canManage ? () => edit(product) : null,
                    trailing: widget.canManage
                        ? IconButton(
                            tooltip: archived ? 'Restore' : 'Archive',
                            icon: Icon(
                              archived
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined,
                            ),
                            onPressed: () => archive(product),
                          )
                        : null,
                  ),
                ),
              if (more && !loading)
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
}
