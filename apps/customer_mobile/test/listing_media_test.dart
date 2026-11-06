import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_core/listing_media.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideo extends VideoPlayerPlatform {
  int created = 0, plays = 0, pauses = 0, disposed = 0;
  double? volume;
  DataSource? source;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    return ++created;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(320, 320),
    ),
  );
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauses++;
  }

  @override
  Future<void> setVolume(int playerId, double value) async {
    volume = value;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> dispose(int playerId) async {
    disposed++;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

void main() {
  testWidgets('listing video streams, pauses out of view and in background', (
    tester,
  ) async {
    final old = VideoPlayerPlatform.instance, video = FakeVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = old);
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: const Column(
              children: [
                SizedBox(
                  height: 300,
                  width: 300,
                  child: ListingVideo(
                    url: 'https://fixture.invalid/listing.mp4',
                    autoPlay: true,
                    showControls: false,
                  ),
                ),
                SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(video.created, 1);
    expect(video.source?.sourceType, DataSourceType.network);
    expect(video.plays, greaterThan(0));
    expect(video.volume, 0);
    expect(find.byType(IconButton), findsNothing);
    final pauses = video.pauses;
    scroll.jumpTo(800);
    await tester.pump();
    expect(video.pauses, greaterThan(pauses));
    scroll.jumpTo(0);
    await tester.pump();
    final backgroundPauses = video.pauses;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(video.pauses, greaterThan(backgroundPauses));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(video.disposed, 1);
    expect(tester.takeException(), isNull);
    scroll.dispose();
  });
  testWidgets('replacing a listing source disposes the previous stream', (
    tester,
  ) async {
    final old = VideoPlayerPlatform.instance, video = FakeVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = old);
    Widget player(String name) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: ListingVideo(url: 'https://fixture.invalid/$name.mp4'),
        ),
      ),
    );
    await tester.pumpWidget(player('first'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(video.created, 1);
    await tester.pumpWidget(player('second'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(video.created, 2);
    expect(video.source?.uri, 'https://fixture.invalid/second.mp4');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(video.disposed, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a media frame taller than the viewport still initializes', (
    tester,
  ) async {
    final old = VideoPlayerPlatform.instance, video = FakeVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = old);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              height: 1600,
              child: ListingVideo(url: 'https://fixture.invalid/portrait.mp4'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(video.created, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('offstage listing videos do not fetch a source', (tester) async {
    final old = VideoPlayerPlatform.instance, video = FakeVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = old);
    await tester.pumpWidget(
      const MaterialApp(
        home: Offstage(
          child: SizedBox(
            width: 300,
            height: 300,
            child: ListingVideo(
              url: 'https://fixture.invalid/hidden.mp4',
              autoPlay: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(video.created, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
