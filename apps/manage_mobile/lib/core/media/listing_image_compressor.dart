import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Produces a web-friendly listing image while keeping enough detail for
/// full-screen viewing. The first pass that reaches the target is retained;
/// otherwise the smallest high-quality pass is used.
class ListingImageCompressor {
  const ListingImageCompressor();

  static const int targetBytes = 420 * 1024;

  Future<XFile> compress(XFile source) async {
    final original = await source.readAsBytes();
    if (original.isEmpty) {
      throw StateError('The selected image is empty. Choose another image.');
    }

    Uint8List? smallest;
    const passes = <({int width, int quality})>[
      (width: 1920, quality: 84),
      (width: 1600, quality: 80),
      (width: 1440, quality: 76),
      (width: 1280, quality: 72),
    ];

    for (final pass in passes) {
      final bytes = await FlutterImageCompress.compressWithList(
        original,
        minWidth: pass.width,
        minHeight: pass.width,
        quality: pass.quality,
        format: CompressFormat.jpeg,
        autoCorrectionAngle: true,
        keepExif: false,
      );
      if (bytes.isEmpty) continue;
      if (smallest == null || bytes.length < smallest.length) smallest = bytes;
      if (bytes.length <= targetBytes) {
        return _asJpeg(source, bytes);
      }
    }

    if (smallest == null) {
      throw StateError(
        'This image could not be prepared. Choose another image.',
      );
    }
    return _asJpeg(source, smallest);
  }

  Future<List<XFile>> compressAll(List<XFile> sources) async {
    final output = <XFile>[];
    for (final source in sources) {
      output.add(await compress(source));
    }
    return output;
  }

  XFile _asJpeg(XFile source, Uint8List bytes) {
    final dot = source.name.lastIndexOf('.');
    final originalBase = dot > 0 ? source.name.substring(0, dot) : source.name;
    final base = originalBase.trim().isEmpty ? 'listing-image' : originalBase;
    return XFile.fromData(
      bytes,
      name: '${base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')}.jpg',
      mimeType: 'image/jpeg',
    );
  }
}
