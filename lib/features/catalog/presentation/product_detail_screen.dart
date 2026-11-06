import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/catalog_repository.dart';
import '../domain/product_detail_repository.dart';
import '../data/supabase_product_detail_repository.dart';
import 'product_editor.dart';
import 'product_image_screen.dart';

final productDetailRepositoryProvider = Provider<ProductDetailRepository>(
  (ref) => SupabaseProductDetailRepository(ref.watch(supabaseClientProvider)),
);

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.organizationId,
    required this.productId,
    required this.canManage,
  });
  final String organizationId, productId;
  final bool canManage;
  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailState();
}

class _ProductDetailState extends ConsumerState<ProductDetailScreen>
    with WidgetsBindingObserver {
  late Future<CatalogProduct> detail;
  bool opening = false;
  void reload() {
    detail = ref
        .read(productDetailRepositoryProvider)
        .load(widget.organizationId, widget.productId);
    // Refresh can fail before the next frame attaches FutureBuilder's listener.
    detail.ignore();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProductDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.productId != widget.productId ||
        oldWidget.canManage != widget.canManage) {
      reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(reload);
  }

  Future<void> open(CatalogProduct product, {required bool image}) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => image
              ? ProductImageScreen(
                  organizationId: widget.organizationId,
                  product: product,
                  canManage: widget.canManage,
                )
              : ProductEditor(
                  organizationId: widget.organizationId,
                  product: product,
                ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          opening = false;
          reload();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Product details'),
      actions: [
        IconButton(
          tooltip: 'Refresh product',
          onPressed: opening ? null : () => setState(reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<CatalogProduct>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Product unavailable. It may have been removed or your business access may have changed.',
                    ),
                    FilledButton(
                      onPressed: () => setState(reload),
                      child: const Text('Retry product'),
                    ),
                  ],
                ),
              ),
            );
          }
          final product = snapshot.data!;
          final values = product.values;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                product.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(values['active'] == true ? 'Active' : 'Archived'),
              for (final entry in {
                'type': 'Type',
                'sku': 'SKU',
                'barcode': 'Barcode',
                'category': 'Category',
                'unit': 'Unit',
                'hsn_sac': 'HSN / SAC',
                'sale_price': 'Sale price (INR)',
                'purchase_price': 'Purchase price (INR)',
                'tax_percent': 'GST (%)',
                'reorder_level': 'Reorder level',
              }.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  subtitle: SelectableText('${values[entry.key] ?? 'Not set'}'),
                ),
              Text(
                values['price_includes_tax'] == true
                    ? 'Prices include tax'
                    : 'Tax added to prices',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: opening ? null : () => open(product, image: true),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Product image'),
              ),
              if (widget.canManage)
                FilledButton.icon(
                  onPressed: opening ? null : () => open(product, image: false),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit product'),
                ),
            ],
          );
        },
      ),
    ),
  );
}
