import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

abstract class ImageUtils {
  ImageUtils._();

  /// Compresses the image from [file] and strips EXIF metadata (since `keepExif` defaults to `false`).
  static Future<Uint8List> compressAndStripExif(File file, {int quality = 70, int minWidth = 1080, int minHeight = 1080}) async {
    final origBytes = await file.readAsBytes();
    final compressedBytes = await FlutterImageCompress.compressWithList(
      origBytes,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      keepExif: false, // Explicitly false to strip location and other EXIF metadata (#13)
    );
    return compressedBytes;
  }

  /// If the file is larger than 5 MB, compresses it and returns the compressed File.
  /// Otherwise returns the original File.
  static Future<File> compressIfNeeded(File file) async {
    final length = await file.length();
    final double sizeInMb = length / (1024 * 1024);
    if (sizeInMb <= 5.0) {
      return file;
    }
    final bytes = await compressAndStripExif(file, quality: 60);
    final tempDir = file.parent;
    final tempFile = File('${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(bytes);
    return tempFile;
  }
}
