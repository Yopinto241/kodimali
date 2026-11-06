import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import 'localized_ui.dart';

final _listingImages = CacheManager(
  Config(
    'kodimaliListingImages',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 250,
  ),
);

class ListingImage extends StatelessWidget {
  const ListingImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.cacheManager,
    this.fit = BoxFit.contain,
    this.maxDecodeWidth = 1600,
  });
  final String url;
  final String? cacheKey;
  final BaseCacheManager? cacheManager;
  final BoxFit fit;
  final int maxDecodeWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final decoded = (width * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(160, maxDecodeWidth);
      return CachedNetworkImage(
        imageUrl: url,
        cacheKey: cacheKey ?? url,
        cacheManager: cacheManager ?? _listingImages,
        fit: fit,
        memCacheWidth: decoded,
        maxWidthDiskCache: maxDecodeWidth,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        errorWidget: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    },
  );
}

/// Streams the first playable bytes instead of downloading the entire file.
/// Enclosing scroll viewports and app lifecycle control decoding/playback.
class ListingVideo extends StatefulWidget {
  const ListingVideo({
    super.key,
    required this.url,
    this.autoPlay = false,
    this.showControls = true,
  });
  final String url;
  final bool autoPlay;
  final bool showControls;
  @override
  State<ListingVideo> createState() => _ListingVideoState();
}

class _ListingVideoState extends State<ListingVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  final Set<ScrollPosition> _positions = {};
  final List<ScrollableState> _scrollables = [];
  bool _resumed = true, _muted = true, _loading = false, _failed = false;
  bool _wantsPlay = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _wantsPlay = widget.autoPlay;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ListingVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _generation++;
      _controller?.dispose();
      _controller = null;
      _loading = false;
      _failed = false;
      _wantsPlay = widget.autoPlay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _check();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final position in _positions) {
      position.removeListener(_check);
    }
    _positions.clear();
    _scrollables.clear();
    Scrollable.maybeOf(context);
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        _scrollables.add(scrollable);
        _positions.add(scrollable.position);
      }
      return true;
    });
    for (final position in _positions) {
      position.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  void _check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    bool visible =
        _resumed &&
        ModalRoute.of(context)?.isCurrent != false &&
        TickerMode.valuesOf(context).enabled;
    context.visitAncestorElements((element) {
      if (element.widget case Offstage(offstage: true)) visible = false;
      return visible;
    });
    if (box is RenderBox && box.hasSize && box.attached) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      var viewportBounds = Offset.zero & MediaQuery.sizeOf(context);
      for (final scrollable in _scrollables) {
        final viewport = scrollable.context.findRenderObject();
        if (viewport is RenderBox && viewport.hasSize && viewport.attached) {
          viewportBounds = viewportBounds.intersect(
            viewport.localToGlobal(Offset.zero) & viewport.size,
          );
        }
      }
      final clipped = rect.intersect(viewportBounds);
      // A large portrait frame can exceed a landscape/tablet viewport. Compare
      // with its viewable area so it can still initialize and play there.
      final viewableArea =
          rect.width.clamp(
            0.0,
            viewportBounds.width.clamp(0.0, double.infinity),
          ) *
          rect.height.clamp(
            0.0,
            viewportBounds.height.clamp(0.0, double.infinity),
          );
      visible =
          visible &&
          !clipped.isEmpty &&
          viewableArea > 0 &&
          clipped.width * clipped.height >= viewableArea * .5;
    } else {
      visible = false;
    }
    if (visible && _controller == null && !_loading && !_failed) {
      unawaited(_initialize());
    }
    final controller = _controller;
    if (controller?.value.isInitialized == true) {
      if (visible && _wantsPlay && !controller!.value.isPlaying) {
        unawaited(controller.play());
      } else if ((!visible || !_wantsPlay) && controller!.value.isPlaying) {
        unawaited(controller.pause());
      }
    }
  }

  Future<void> _initialize() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || generation != _generation) return;
      await controller.setLooping(widget.autoPlay);
      if (!mounted || generation != _generation) return;
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
      });
      _check();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _controller = null;
      await controller.dispose();
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _check();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    for (final position in _positions) {
      position.removeListener(_check);
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller?.value.isInitialized == true)
            Center(
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_failed)
            Center(
              child: TextButton.icon(
                onPressed: _initialize,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const LocalizedUiText(
                  'Retry video',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          if (widget.showControls && !_loading && !_failed)
            Center(
              child: IconButton.filledTonal(
                tooltip: mobileUi(
                  context,
                  _wantsPlay ? 'Pause video' : 'Play video',
                ),
                iconSize: 36,
                icon: Icon(
                  _wantsPlay ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: () {
                  setState(() {
                    _wantsPlay = !_wantsPlay;
                  });
                  _check();
                },
              ),
            ),
          if (widget.showControls && controller?.value.isInitialized == true)
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Column(
                children: [
                  VideoProgressIndicator(
                    controller!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: mobileUi(
                        context,
                        _muted ? 'Unmute video' : 'Mute video',
                      ),
                      color: Colors.white,
                      icon: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                      ),
                      onPressed: () {
                        setState(() {
                          _muted = !_muted;
                        });
                        controller.setVolume(_muted ? 0 : 1);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
