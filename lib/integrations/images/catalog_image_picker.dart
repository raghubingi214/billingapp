import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

Uint8List optimizeCatalogImage(Uint8List bytes) {
  if (bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Image is too large');
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width * decoded.height > 24000000) {
    throw const FormatException('Unsupported image');
  }
  final oriented = img.bakeOrientation(decoded);
  final resized = oriented.width > 1280 || oriented.height > 1280
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1280 : null,
          height: oriented.height > oriented.width ? 1280 : null,
        )
      : oriented;
  final result = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  if (result.length > 3 * 1024 * 1024) {
    throw const FormatException('Optimized image is too large');
  }
  return result;
}

class CatalogImagePicker {
  Future<Uint8List?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (file == null) return null;
    return compute(optimizeCatalogImage, await file.readAsBytes());
  }
}
