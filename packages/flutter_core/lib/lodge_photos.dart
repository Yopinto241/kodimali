import 'package:flutter/material.dart';
import 'lodge_api.dart';
import 'listing_media.dart';
import 'localized_ui.dart';

class LodgePhotoPreview extends StatefulWidget {
  const LodgePhotoPreview({super.key, required this.api, required this.paths});
  final LodgeApi api;
  final List<String> paths;
  @override
  State<LodgePhotoPreview> createState() => _LodgePhotoPreviewState();
}

class _LodgePhotoPreviewState extends State<LodgePhotoPreview> {
  String _key = '';
  late Future<Map<String, String>> _images;
  void _load() {
    _key = widget.paths.join('|');
    _images = widget.api.images(List.of(widget.paths));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LodgePhotoPreview old) {
    super.didUpdateWidget(old);
    if (_key != widget.paths.join('|') || old.api != widget.api) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paths.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Map<String, String>>(
      future: _images,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const LocalizedUiText('Image could not load');
        }
        final images = snapshot.data ?? {};
        return SizedBox(
          height: 160,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final entry in images.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 200,
                    child: GestureDetector(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => Dialog.fullscreen(
                          child: Scaffold(
                            appBar: AppBar(
                              title: const LocalizedUiText('Photo'),
                            ),
                            body: InteractiveViewer(
                              child: Center(
                                child: ListingImage(
                                  url: entry.value,
                                  cacheKey: entry.key,
                                  maxDecodeWidth: 2400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: ListingImage(
                        url: entry.value,
                        cacheKey: entry.key,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
