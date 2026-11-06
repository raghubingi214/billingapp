import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/images/catalog_image_picker.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_catalog_image_repository.dart';
import '../domain/catalog_image_repository.dart';
import '../domain/catalog_repository.dart';

final catalogImageRepositoryProvider = Provider<CatalogImageRepository>(
  (ref) => SupabaseCatalogImageRepository(ref.watch(supabaseClientProvider)),
);
final catalogImagePickerProvider = Provider<CatalogImagePicker>(
  (ref) => CatalogImagePicker(),
);

class ProductImageScreen extends ConsumerStatefulWidget {
  const ProductImageScreen({
    super.key,
    required this.organizationId,
    required this.product,
    required this.canManage,
  });
  final String organizationId;
  final CatalogProduct product;
  final bool canManage;
  @override
  ConsumerState<ProductImageScreen> createState() => _ProductImageState();
}

class _ProductImageState extends ConsumerState<ProductImageScreen>
    with WidgetsBindingObserver {
  Uint8List? selected;
  Future<String>? url;
  String? path, command, error;
  bool busy = false, uploaded = false;
  String? removalCommand;
  Timer? imageRefreshTimer;
  Future<void> remove() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove product image?'),
        content: Text(widget.product.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    removalCommand ??= const Uuid().v4();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(catalogImageRepositoryProvider)
          .attach(
            removalCommand!,
            widget.organizationId,
            widget.product.id,
            widget.product.version,
            null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Removal could not be confirmed. Retry, or refresh the product if it changed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final existing = widget.product.values['image_path'];
    if (existing is String) {
      url = ref.read(catalogImageRepositoryProvider).signedUrl(existing);
      url!.ignore();
      scheduleImageRefresh();
    }
  }

  void scheduleImageRefresh() {
    imageRefreshTimer?.cancel();
    // Signed links expire after five minutes, including while viewing the page.
    imageRefreshTimer = Timer(const Duration(minutes: 4), refreshImage);
  }

  @override
  void dispose() {
    imageRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void refreshImage() {
    final existing = widget.product.values['image_path'];
    if (existing is String && selected == null) {
      final refreshed = ref
          .read(catalogImageRepositoryProvider)
          .signedUrl(existing);
      // Observe immediate failures while the next frame attaches FutureBuilder.
      refreshed.ignore();
      setState(() {
        url = refreshed;
      });
      scheduleImageRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    imageRefreshTimer?.cancel();
    if (state == AppLifecycleState.resumed) refreshImage();
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bytes = await ref.read(catalogImagePickerProvider).pick();
      if (!mounted || bytes == null) return;
      setState(() {
        selected = bytes;
        path =
            '${widget.organizationId}/${widget.product.id}/${const Uuid().v4()}.jpg';
        command = const Uuid().v4();
        uploaded = false;
      });
      imageRefreshTimer?.cancel();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to open this image. Choose another photo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || selected == null) return;
    final repository = ref.read(catalogImageRepositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!uploaded) {
        await repository.upload(path!, selected!);
        uploaded = true;
      }
      await repository.attach(
        command!,
        widget.organizationId,
        widget.product.id,
        widget.product.version,
        path,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Image could not be confirmed. Retry, or refresh the product if it changed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Product image')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.product.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (selected != null)
            Image.memory(selected!, height: 260, fit: BoxFit.contain)
          else if (url != null)
            FutureBuilder<String>(
              future: url,
              builder: (context, snapshot) => snapshot.hasError
                  ? TextButton(
                      onPressed: refreshImage,
                      child: const Text('Retry image'),
                    )
                  : snapshot.hasData
                  ? Image.network(
                      snapshot.data!,
                      height: 260,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => TextButton(
                        onPressed: refreshImage,
                        child: const Text('Retry image'),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            )
          else
            const Text('No image attached.'),
          if (error != null) Text(error!),
          if (widget.canManage) ...[
            const SizedBox(height: 20),
            if (widget.product.values['image_path'] != null)
              TextButton(
                onPressed: busy ? null : remove,
                child: const Text('Remove image'),
              ),
            OutlinedButton(
              onPressed: busy ? null : pick,
              child: const Text('Choose photo'),
            ),
            FilledButton(
              onPressed: busy || selected == null ? null : save,
              child: Text(busy ? 'Working…' : 'Save image'),
            ),
          ],
        ],
      ),
    ),
  );
}
