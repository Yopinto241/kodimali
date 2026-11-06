import 'package:flutter/material.dart';
import 'package:flutter_core/listing_media.dart';
import 'package:flutter_core/localized_ui.dart';

class ManageListingMediaGallery extends StatefulWidget {
  const ManageListingMediaGallery({super.key, required this.media});
  final List<dynamic> media;
  @override
  State<ManageListingMediaGallery> createState() =>
      _ManageListingMediaGalleryState();
}

class _ManageListingMediaGalleryState extends State<ManageListingMediaGallery> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) {
    final media = widget.media
        .whereType<Map>()
        .where((item) => item['preview_url'] != null)
        .toList();
    if (media.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LocalizedUiText(
                'Photos and videos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text('${_selected + 1} / ${media.length}'),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 4 / 5,
            child: PageView.builder(
              itemCount: media.length,
              onPageChanged: (index) => setState(() {
                _selected = index;
              }),
              itemBuilder: (context, index) {
                final item = media[index];
                final url = item['preview_url'].toString();
                if (item['media_type'] == 'video') {
                  return index == _selected
                      ? ListingVideo(
                          key: ValueKey(item['storage_path']),
                          url: url,
                        )
                      : const ColoredBox(color: Colors.black);
                }
                return Material(
                  child: InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog.fullscreen(
                        child: Scaffold(
                          appBar: AppBar(title: const LocalizedUiText('Photo')),
                          body: InteractiveViewer(
                            child: Center(
                              child: ListingImage(
                                url: url,
                                cacheKey: item['storage_path']?.toString(),
                                maxDecodeWidth: 2400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: ListingImage(
                      url: url,
                      cacheKey: item['storage_path']?.toString(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        const LocalizedUiText('Swipe to see more. Tap a photo to enlarge.'),
      ],
    );
  }
}
