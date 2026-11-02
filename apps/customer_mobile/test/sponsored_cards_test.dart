import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_design_system/flutter_design_system.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:customer_mobile/app.dart';
import 'mobile_ui_test.dart' show host;

class FakeVideo extends VideoPlayerPlatform {
  int created = 0, plays = 0, pauses = 0, disposed = 0;
  double? volume;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++created;
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
  testWidgets('changing campaigns replaces the previous video player', (
    tester,
  ) async {
    final old = VideoPlayerPlatform.instance, video = FakeVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = old);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    Widget card(String id) => host(
      Scaffold(
        body: SingleChildScrollView(
          child: CustomerSponsoredCards(
            promotions: [
              {
                'promotion_id': id,
                'title': id,
                'media_type': 'video',
                'media_url': 'https://fixture.invalid/$id.mp4',
              },
            ],
          ),
        ),
      ),
      'en',
      KodimaliTheme.mobileLight(),
      1,
    );
    await tester.pumpWidget(card('first'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(video.created, 1);
    await tester.pumpWidget(card('second'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(video.created, 2);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(video.disposed, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('every assigned sponsored card is present without expansion', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: CustomerSponsoredCards(
              promotions: List.generate(
                7,
                (index) => {
                  'promotion_id': 'ad-$index',
                  'title': 'Campaign $index',
                  'description': 'Assigned ad',
                },
              ),
            ),
          ),
        ),
        'en',
        KodimaliTheme.mobileLight(),
        1,
      ),
    );
    await tester.pumpAndSettle();
    for (var index = 0; index < 7; index++) {
      expect(find.text('Campaign $index'), findsOneWidget);
    }
    expect(tester.getTopLeft(find.text('Campaign 6')).dx, greaterThan(800));
    await tester.ensureVisible(find.text('Campaign 6'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Campaign 6')).dx, lessThan(800));
    expect(find.textContaining('More sponsored'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'ad video starts muted when visible and pauses off-screen and in background',
    (tester) async {
      final old = VideoPlayerPlatform.instance, video = FakeVideo();
      VideoPlayerPlatform.instance = video;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  CustomerSponsoredCards(
                    promotions: const [
                      {
                        'promotion_id': 'video',
                        'title': 'Video campaign',
                        'media_type': 'video',
                        'media_url': 'https://fixture.invalid/ad.mp4',
                      },
                    ],
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
          'en',
          KodimaliTheme.mobileLight(),
          1,
        ),
      );
      await tester.pump();
      expect(video.created, 0);
      scroll.jumpTo(950);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(video.created, 1);
      expect(video.volume, 0);
      expect(video.plays, greaterThan(0));
      final before = video.pauses;
      scroll.jumpTo(0);
      await tester.pump();
      expect(video.pauses, greaterThan(before));
      scroll.jumpTo(950);
      await tester.pump();
      final pauses = video.pauses;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(video.pauses, greaterThan(pauses));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(video.disposed, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
