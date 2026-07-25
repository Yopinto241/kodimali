import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'listing_media_validator.dart';

typedef ListingVideoCompressionProgress = void Function(double progress);

class ListingVideoCompressionResult {
  const ListingVideoCompressionResult({
    required this.video,
    required this.originalName,
    required this.originalBytes,
    required this.compressedBytes,
  });

  final XFile video;
  final String originalName;
  final int originalBytes;
  final int compressedBytes;

  double get reductionPercent {
    if (originalBytes <= 0) {
      return 0;
    }
    return ((originalBytes - compressedBytes) / originalBytes * 100)
        .clamp(0, 100)
        .toDouble();
  }
}

class ListingVideoCompressionCancelled implements Exception {
  const ListingVideoCompressionCancelled();
}

class ListingVideoCompressor {
  bool _cancelRequested = false;

  Future<ListingVideoCompressionResult> compress(
    XFile input, {
    ListingVideoCompressionProgress? onProgress,
  }) async {
    _cancelRequested = false;
    final int originalBytes = await ListingMediaValidator.validateVideoInput(
      input,
    );
    await VideoCompress.deleteAllCache();

    final Subscription progressSubscription = VideoCompress.compressProgress$
        .subscribe((double value) {
          onProgress?.call((value / 100).clamp(0, 1).toDouble());
        });

    try {
      final List<VideoQuality> attempts = <VideoQuality>[
        VideoQuality.MediumQuality,
        VideoQuality.LowQuality,
      ];
      int? smallestBytes;
      for (final VideoQuality quality in attempts) {
        _throwIfCancelled();
        final MediaInfo? media = await VideoCompress.compressVideo(
          input.path,
          quality: quality,
          deleteOrigin: false,
          includeAudio: true,
          frameRate: 30,
        );
        _throwIfCancelled();
        if (media == null || media.isCancel == true || media.file == null) {
          throw StateError(
            'Video compression did not finish. Select the video and try again.',
          );
        }
        final int compressedBytes = await media.file!.length();
        if (compressedBytes <= 0) {
          throw StateError(
            'Video compression produced an empty file. Select another video.',
          );
        }
        if (smallestBytes == null || compressedBytes < smallestBytes) {
          smallestBytes = compressedBytes;
        }
        if (compressedBytes <=
            ListingMediaValidator.compressedVideoTargetBytes) {
          final String outputName =
              'kodimali-listing-${DateTime.now().millisecondsSinceEpoch}.mp4';
          final XFile output = XFile(
            media.file!.path,
            name: outputName,
            mimeType: 'video/mp4',
          );
          await ListingMediaValidator.validateCompressedVideo(output);
          onProgress?.call(1);
          return ListingVideoCompressionResult(
            video: output,
            originalName: input.name,
            originalBytes: originalBytes,
            compressedBytes: compressedBytes,
          );
        }
      }

      await clearCache();
      throw StateError(
        'The video is still '
        '${ListingMediaValidator.formatMiB(smallestBytes ?? originalBytes)} '
        'after strong compression. Shorten the video or choose a smaller one; '
        'the prepared upload must stay below 29 MB.',
      );
    } finally {
      progressSubscription.unsubscribe();
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    await VideoCompress.cancelCompression();
  }

  Future<void> clearCache() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {
      // Temporary cache cleanup is best effort.
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const ListingVideoCompressionCancelled();
    }
  }
}
