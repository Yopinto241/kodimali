import 'package:image_picker/image_picker.dart';

class ListingMediaValidator {
  const ListingMediaValidator._();

  /// Matches the current Supabase `listing-media` bucket limit.
  static const int serverFileMaxBytes = 30 * 1024 * 1024;

  /// Leaves one MiB below the storage limit for a deterministic client guard.
  static const int compressedVideoTargetBytes = 29 * 1024 * 1024;

  static const Set<String> imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
  };

  /// These containers are supported by both AVFoundation and Android's native
  /// transcoder used by the listing compression pipeline.
  static const Set<String> compressibleVideoExtensions = <String>{
    'mp4',
    'mov',
    'm4v',
  };

  static Future<void> validateImages(List<XFile> images) async {
    if (images.isEmpty) {
      throw StateError('Add at least one listing image before publishing.');
    }
    for (int index = 0; index < images.length; index += 1) {
      final XFile image = images[index];
      String extension = imageExtensionOf(image);
      final int bytes = await image.length();
      if (extension.isEmpty && bytes > 0) {
        extension = _extensionFromHeader(await image.readAsBytes());
      }
      if (!imageExtensions.contains(extension)) {
        throw StateError(
          'Image ${index + 1} (${image.name}) is not supported. '
          'Use JPG, PNG, WebP, GIF, HEIC, or HEIF.',
        );
      }
      if (bytes <= 0) {
        throw StateError('Image ${index + 1} (${image.name}) is empty.');
      }
      if (bytes > serverFileMaxBytes) {
        throw StateError(
          'Image ${index + 1} (${image.name}) is ${formatMiB(bytes)}, '
          'but each listing file must be 30 MB or smaller.',
        );
      }
    }
  }

  static Future<int> validateVideoInput(XFile video) async {
    final String extension = extensionOf(video.name);
    if (!compressibleVideoExtensions.contains(extension)) {
      throw StateError(
        'This video format cannot be compressed reliably on both Android and '
        'iPhone. Choose an MP4, MOV, or M4V video.',
      );
    }
    final int bytes = await video.length();
    if (bytes <= 0) {
      throw StateError('The selected video is empty or cannot be read.');
    }
    return bytes;
  }

  static Future<int> validateCompressedVideo(XFile video) async {
    if (extensionOf(video.name) != 'mp4') {
      throw StateError(
        'The prepared listing video must be an MP4 file. Select it again.',
      );
    }
    final int bytes = await video.length();
    if (bytes <= 0) {
      throw StateError('The prepared listing video is empty. Select it again.');
    }
    if (bytes > serverFileMaxBytes) {
      throw StateError(
        'The prepared video is ${formatMiB(bytes)}. The final upload must be '
        '30 MB or smaller.',
      );
    }
    return bytes;
  }

  static String extensionOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String imageExtensionOf(XFile image) {
    final String namedExtension = extensionOf(image.name);
    if (namedExtension.isNotEmpty) return namedExtension;
    final String pathExtension = extensionOf(image.path);
    if (pathExtension.isNotEmpty) return pathExtension;
    return switch (image.mimeType?.toLowerCase()) {
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => '',
    };
  }

  static String _extensionFromHeader(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    if (bytes.length >= 6 &&
        String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF') {
      return 'gif';
    }
    return '';
  }

  static String formatMiB(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
