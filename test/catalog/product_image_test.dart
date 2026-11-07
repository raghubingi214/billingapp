import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/catalog/data/pending_product_image_store.dart';
import 'package:smart_billing/features/catalog/domain/catalog_image_repository.dart';
import 'package:smart_billing/features/catalog/domain/catalog_repository.dart';
import 'package:smart_billing/features/catalog/presentation/product_image_screen.dart';
import 'package:smart_billing/integrations/images/catalog_image_picker.dart';

class _Picker extends CatalogImagePicker {
  @override
  Future<Uint8List?> pick() async =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 10, height: 10)));
}

class _Repository implements CatalogImageRepository {
  int signedCalls = 0;
  bool failSigning = false;
  int uploads = 0;
  Completer<void>? attachmentResponse;
  final commands = <String>[];
  @override
  Future<void> upload(String path, Uint8List jpeg) async {
    uploads++;
  }

  @override
  Future<void> attach(
    String requestId,
    String organizationId,
    String productId,
    int version,
    String? path,
  ) async {
    commands.add('$requestId:$organizationId:$productId:$version:$path');
    await attachmentResponse?.future;
    throw StateError('Response lost');
  }

  @override
  Future<String> signedUrl(String path) async {
    signedCalls++;
    if (failSigning) throw StateError('Unable to sign');
    return 'https://example.invalid/image';
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('pending image commands stay scoped and cannot be replaced', () async {
    final store = PendingProductImageStore('actor-a', 'org-a', 'product-a');
    const change = (requestId: 'request-a', version: 3, path: null);
    const other = (requestId: 'request-b', version: 4, path: 'photo.jpg');
    await store.save(change);
    expect(await store.read(), change);
    expect(
      await PendingProductImageStore('actor-b', 'org-a', 'product-a').read(),
      isNull,
    );
    expect(
      await PendingProductImageStore('actor-a', 'org-b', 'product-a').read(),
      isNull,
    );
    expect(
      await PendingProductImageStore('actor-a', 'org-a', 'product-b').read(),
      isNull,
    );
    await expectLater(store.save(other), throwsStateError);
    await expectLater(store.clear(other), throwsStateError);
    expect(await store.read(), change);
    await store.clear(change);
    expect(await store.read(), isNull);
  });
  testWidgets('signed image renews before expiry and stops after disposal', (
    tester,
  ) async {
    final repository = _Repository()..failSigning = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogImageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: ProductImageScreen(
            organizationId: 'org-a',
            product: CatalogProduct(
              id: 'product-a',
              version: 3,
              name: 'Rice',
              type: 'product',
              values: {'image_path': 'org/product/asset.jpg'},
            ),
            canManage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.signedCalls, 1);
    await tester.pump(const Duration(minutes: 4));
    await tester.pumpAndSettle();
    expect(repository.signedCalls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
    expect(repository.signedCalls, 2);
    expect(repository.commands, isEmpty);
  });
  testWidgets('failed signed image can retry without reopening', (
    tester,
  ) async {
    final repository = _Repository()..failSigning = true;
    const existing = CatalogProduct(
      id: 'product-a',
      version: 3,
      name: 'Rice',
      type: 'product',
      values: {'image_path': 'org/product/asset.jpg'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogImageRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: ProductImageScreen(
            organizationId: 'org-a',
            product: existing,
            canManage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.signedCalls, 1);
    await tester.tap(find.text('Retry image'));
    await tester.pumpAndSettle();
    expect(repository.signedCalls, 2);
    expect(repository.commands, isEmpty);
  });
  testWidgets(
    'image removal requires confirmation and uses versioned attachment command',
    (tester) async {
      final repository = _Repository();
      const existing = CatalogProduct(
        id: 'product-a',
        version: 3,
        name: 'Rice',
        type: 'product',
        values: {'image_path': 'org/product/asset.jpg'},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogImageRepositoryProvider.overrideWithValue(repository),
            catalogImageActorProvider.overrideWithValue('actor-a'),
          ],
          child: const MaterialApp(
            home: ProductImageScreen(
              organizationId: 'org-a',
              product: existing,
              canManage: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove image'));
      await tester.tap(find.text('Remove image'));
      await tester.pumpAndSettle();
      expect(repository.commands, isEmpty);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(repository.commands.single, endsWith(':org-a:product-a:3:null'));
      expect(repository.uploads, 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Choose photo'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Retry removal'));
      await tester.tap(find.text('Retry removal'));
      await tester.pumpAndSettle();
      expect(repository.commands.length, 2);
      expect(repository.commands.first, repository.commands.last);
    },
  );
  const product = CatalogProduct(
    id: 'product-a',
    version: 3,
    name: 'Rice',
    type: 'product',
    values: {},
  );
  testWidgets('attachment retry retains command and skips completed upload', (
    tester,
  ) async {
    final response = Completer<void>();
    final repository = _Repository()..attachmentResponse = response;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogImageRepositoryProvider.overrideWithValue(repository),
          catalogImagePickerProvider.overrideWithValue(_Picker()),
          catalogImageActorProvider.overrideWithValue('actor-a'),
        ],
        child: const MaterialApp(
          home: ProductImageScreen(
            organizationId: 'org-a',
            product: CatalogProduct(
              id: 'product-a',
              version: 3,
              name: 'Rice',
              type: 'product',
              values: {'image_path': 'org/product/asset.jpg'},
            ),
            canManage: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save image'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(
      tester.element(find.byType(ProductImageScreen)),
    )!;
    expect(route.popDisposition, RoutePopDisposition.doNotPop);
    response.complete();
    await tester.pumpAndSettle();
    expect(route.popDisposition, isNot(RoutePopDisposition.doNotPop));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Remove image'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose photo'),
          )
          .onPressed,
      isNull,
    );
    final screen = tester.widget<ProviderScope>(
      find.byType(ProviderScope).first,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Retry save'));
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(repository.uploads, 1);
    expect(repository.commands.length, 2);
    expect(repository.commands.first, repository.commands.last);
  });
  testWidgets('read-only product image has no write actions', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ProductImageScreen(
            organizationId: 'org-a',
            product: product,
            canManage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose photo'), findsNothing);
    expect(find.text('Save image'), findsNothing);
    expect(find.text('No image attached.'), findsOneWidget);
  });
}
