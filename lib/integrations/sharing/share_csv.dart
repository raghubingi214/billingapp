import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareCsv(String csv, String filename, Rect origin) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode('\uFEFF$csv')),
          mimeType: 'text/csv',
        ),
      ],
      fileNameOverrides: [filename],
      sharePositionOrigin: origin,
    ),
  );
}
