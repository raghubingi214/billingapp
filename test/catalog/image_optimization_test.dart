import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_billing/integrations/images/catalog_image_picker.dart';

void main() {
  test('catalog image is encoded as bounded JPEG preserving aspect ratio', () {
    final input = Uint8List.fromList(
      img.encodePng(img.Image(width: 1600, height: 800)),
    );
    final result = optimizeCatalogImage(input);
    final decoded = img.decodeJpg(result)!;
    expect(decoded.width, 1280);
    expect(decoded.height, 640);
    expect(result.length, lessThan(3 * 1024 * 1024));
  });
  test('invalid images are rejected', () {
    expect(
      () => optimizeCatalogImage(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
