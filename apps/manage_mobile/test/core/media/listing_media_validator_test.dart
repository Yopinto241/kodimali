import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:manage_mobile/core/media/listing_media_validator.dart';

XFile _memoryFile(String name, {int length = 1}) {
  return XFile.fromData(
    Uint8List.fromList(<int>[1]),
    path: name,
    name: name,
    length: length,
  );
}

void main() {
  group('ListingMediaValidator limits', () {
    test('keeps compressed video target below the server maximum', () {
      expect(
        ListingMediaValidator.compressedVideoTargetBytes,
        lessThan(ListingMediaValidator.serverFileMaxBytes),
      );
      expect(ListingMediaValidator.serverFileMaxBytes, 30 * 1024 * 1024);
    });

    test('rejects an image above the per-file server maximum', () async {
      final XFile image = _memoryFile(
        'large.jpg',
        length: ListingMediaValidator.serverFileMaxBytes + 1,
      );

      await expectLater(
        ListingMediaValidator.validateImages(<XFile>[image]),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('30 MB or smaller'),
          ),
        ),
      );
    });
  });

  group('ListingMediaValidator file formats', () {
    test('accepts supported image extensions case-insensitively', () async {
      await ListingMediaValidator.validateImages(<XFile>[
        _memoryFile('front.JPG'),
        _memoryFile('kitchen.webp'),
      ]);
    });

    test('rejects unsupported image formats before upload', () async {
      await expectLater(
        ListingMediaValidator.validateImages(<XFile>[
          _memoryFile('document.pdf'),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('allows safe source containers for native compression', () async {
      expect(
        await ListingMediaValidator.validateVideoInput(
          _memoryFile('walkthrough.MOV'),
        ),
        1,
      );
      await expectLater(
        ListingMediaValidator.validateVideoInput(_memoryFile('clip.avi')),
        throwsA(isA<StateError>()),
      );
    });

    test('only accepts an MP4 as the prepared upload', () async {
      expect(
        await ListingMediaValidator.validateCompressedVideo(
          _memoryFile('prepared.mp4'),
        ),
        1,
      );
      await expectLater(
        ListingMediaValidator.validateCompressedVideo(
          _memoryFile('prepared.mov'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('extracts extensions without trusting filename casing', () {
      expect(ListingMediaValidator.extensionOf('home.PnG'), 'png');
      expect(ListingMediaValidator.extensionOf('no-extension'), isEmpty);
      expect(ListingMediaValidator.extensionOf('trailing.'), isEmpty);
    });
  });
}
