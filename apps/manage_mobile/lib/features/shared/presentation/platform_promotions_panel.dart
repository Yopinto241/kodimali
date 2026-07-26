import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/widgets/app_scope.dart';

class PlatformPromotionsPanel extends StatelessWidget {
  const PlatformPromotionsPanel({
    super.key,
    required this.surface,
    this.placement = "global",
    this.title = "Promotions",
  });

  final String surface;
  final String placement;
  final String title;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: AppScope.of(context).repository.fetchPromotionsForSurface(
        surface: surface,
        placement: placement,
        limit: 2,
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
          ) {
            final List<Map<String, dynamic>> promotions =
                snapshot.data ?? <Map<String, dynamic>>[];
            if (snapshot.connectionState == ConnectionState.waiting ||
                promotions.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 20),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ...promotions.map(
                  (Map<String, dynamic> promotion) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PromotionCard(promotion: promotion),
                  ),
                ),
              ],
            );
          },
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.promotion});

  final Map<String, dynamic> promotion;

  Future<void> _openTarget(String targetUrl) async {
    final Uri? uri = Uri.tryParse(targetUrl);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final String? mediaType = promotion["media_type"] as String?;
    final String? mediaUrl = promotion["media_url"] as String?;
    final String? thumbnailUrl = promotion["thumbnail_url"] as String?;
    final String? targetUrl = promotion["target_url"] as String?;
    final String description = promotion["description"] as String? ?? "";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (mediaUrl != null) ...<Widget>[
              if (mediaType == "video")
                _TapToPlayPromotionVideo(
                  videoUrl: mediaUrl,
                  thumbnailUrl: thumbnailUrl,
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      mediaUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
            ],
            Text(
              promotion["title"] as String? ?? "-",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(description),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(mediaType ?? "promotion")),
                Chip(
                  label: Text(promotion["placement"] as String? ?? "global"),
                ),
              ],
            ),
            if (targetUrl != null && targetUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _openTarget(targetUrl),
                child: Text(
                  promotion["cta_label"] as String? ?? "Open promotion",
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TapToPlayPromotionVideo extends StatefulWidget {
  const _TapToPlayPromotionVideo({required this.videoUrl, this.thumbnailUrl});

  final String videoUrl;
  final String? thumbnailUrl;

  @override
  State<_TapToPlayPromotionVideo> createState() =>
      _TapToPlayPromotionVideoState();
}

class _TapToPlayPromotionVideoState extends State<_TapToPlayPromotionVideo> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeAndPlay();
  }

  Future<void> _initializeAndPlay() async {
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _controller = controller;
    await controller.initialize();
    await controller.setVolume(0);
    await controller.setLooping(true);
    if (controller.value.duration > const Duration(milliseconds: 500)) {
      await controller.seekTo(const Duration(milliseconds: 500));
    }
    await controller.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_controller == null) {
      return;
    }

    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    } else {
      await _controller!.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final Widget placeholder = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (widget.thumbnailUrl != null)
          Image.network(widget.thumbnailUrl!, fit: BoxFit.cover)
        else
          Container(color: Colors.black12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 1,
          child: controller == null
              ? placeholder
              : FutureBuilder<void>(
                  future: _initialization,
                  builder:
                      (BuildContext context, AsyncSnapshot<void> snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return placeholder;
                        }
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: controller.value.size.width,
                                height: controller.value.size.height,
                                child: VideoPlayer(controller),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  controller.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                ),
        ),
      ),
    );
  }
}
