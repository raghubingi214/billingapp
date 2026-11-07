import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/images/catalog_image_picker.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/pending_product_image_store.dart';
import '../data/supabase_catalog_image_repository.dart';
import '../domain/catalog_image_repository.dart';
import '../domain/catalog_repository.dart';

final catalogImageRepositoryProvider = Provider<CatalogImageRepository>(
  (ref) => SupabaseCatalogImageRepository(ref.watch(supabaseClientProvider)),
);
final catalogImagePickerProvider = Provider<CatalogImagePicker>(
  (ref) => CatalogImagePicker(),
);
final catalogImageActorProvider = Provider<String?>(
  (ref) => ref.watch(authSessionProvider).asData?.value?.userId,
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
  bool ready = false;
  String? actor;
  PendingProductImageStore? store;
  ProductImageCommand? pending;
  Timer? imageRefreshTimer;

  bool get canWrite =>
      ready && actor != null && actor == ref.read(catalogImageActorProvider);

  Future<void> remove() async {
    if (busy || pending?.path != null || !widget.canManage || !canWrite) return;
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
    if (!mounted || confirmed != true || busy || !canWrite || pending != null) {
      return;
    }
    await submit((
      requestId: const Uuid().v4(),
      version: widget.product.version,
      path: null,
    ));
  }

  Future<void> restore() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      actor = ref.read(catalogImageActorProvider);
      final user = actor;
      if (user == null) throw StateError('No signed-in user');
      store = PendingProductImageStore(
        user,
        widget.organizationId,
        widget.product.id,
      );
      pending = await store!.read();
      ready = true;
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load pending image changes.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.canManage) unawaited(restore());
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
    if (busy || pending != null || !canWrite || !widget.canManage) {
      return;
    }
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
    if (busy ||
        selected == null ||
        pending != null ||
        !widget.canManage ||
        !canWrite) {
      return;
    }
    await submit((
      requestId: command!,
      version: widget.product.version,
      path: path,
    ));
  }

  Future<void> submit(ProductImageCommand change) async {
    if (busy || !widget.canManage || !canWrite) return;
    final repository = ref.read(catalogImageRepositoryProvider);
    final journal = store!;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (pending == null) {
        if (change.path != null && !uploaded) {
          await repository.upload(change.path!, selected!);
          uploaded = true;
        }
        if (!mounted || !canWrite) return;
        await journal.save(change);
        pending = change;
      }
      if (!mounted || !canWrite) return;
      try {
        await repository.attach(
          change.requestId,
          widget.organizationId,
          widget.product.id,
          change.version,
          change.path,
        );
      } on ProductImageRejected {
        await journal.clear(change);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Image change rejected. Open the refreshed product to try again.',
              ),
            ),
          );
          Navigator.of(context).pop(true);
        }
        return;
      }
      await journal.clear(change);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Image change could not be confirmed. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeActor = widget.canManage
        ? ref.watch(catalogImageActorProvider)
        : null;
    final canEdit = ready && actor != null && actor == activeActor && !busy;
    final change = pending;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
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
              if (change != null) ...[
                const Text(
                  'An image change is awaiting confirmation. Retry the same action before making another change.',
                ),
                FilledButton(
                  onPressed: canEdit ? () => submit(change) : null,
                  child: Text(
                    change.path == null ? 'Retry removal' : 'Retry save',
                  ),
                ),
              ],
              if (widget.canManage) ...[
                const SizedBox(height: 20),
                if (!ready && !busy)
                  TextButton(
                    onPressed: restore,
                    child: const Text('Reload pending changes'),
                  ),
                if (widget.product.values['image_path'] != null)
                  TextButton(
                    onPressed: canEdit && change == null ? remove : null,
                    child: const Text('Remove image'),
                  ),
                OutlinedButton(
                  onPressed: canEdit && change == null ? pick : null,
                  child: const Text('Choose photo'),
                ),
                FilledButton(
                  onPressed: canEdit && selected != null && change == null
                      ? save
                      : null,
                  child: Text(busy ? 'Working…' : 'Save image'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
