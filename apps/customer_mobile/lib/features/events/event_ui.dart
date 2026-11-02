import 'package:flutter/material.dart';
import '../../core/data/customer_public_repository.dart';

String eventServiceLabel(dynamic value, bool sw) {
  const names = <String, List<String>>{
    'mc_host': ['MC / host', 'MC / mshereheshaji'],
    'dj': ['DJ', 'DJ'],
    'performer': ['Performer', 'Msanii'],
    'choir_group': ['Choir / group', 'Kwaya / kikundi'],
    'photographer': ['Photographer', 'Mpiga picha'],
    'videographer': ['Videographer', 'Mpiga video'],
    'planner': ['Event planner', 'Mpangaji wa tukio'],
    'decorator': ['Decorator', 'Mpambaji'],
    'caterer': ['Catering', 'Huduma ya chakula'],
    'cook': ['Cook', 'Mpishi'],
    'usher': ['Usher', 'Mkaribishaji'],
    'hospitality': ['Hospitality', 'Ukarimu'],
    'cleaning_team': ['Cleaning team', 'Usafi'],
    'transport_delivery': ['Transport / delivery', 'Usafiri'],
    'other': ['Other services', 'Huduma nyingine'],
  };
  return names[value]?[sw ? 1 : 0] ?? (sw ? 'Huduma' : 'Service');
}

String eventPriceLabel(JsonMap item, bool sw) {
  final value = item['price_amount_tzs'];
  if (value == null) return sw ? 'Omba bei' : 'Request a quote';
  final amount = value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  final unit = <String, String>{
    'item_hour': sw ? 'kwa kifaa / saa' : 'per item / hour',
    'item_day': sw ? 'kwa kifaa / siku' : 'per item / day',
    'item_event': sw ? 'kwa kifaa / tukio' : 'per item / event',
    'fixed': sw ? 'bei maalumu' : 'fixed price',
  }[item['price_unit']];
  return unit == null
      ? '${sw ? 'Kuanzia' : 'From'} TZS $amount'
      : 'TZS $amount / $unit';
}

String eventDateLabel(BuildContext context, DateTime date) =>
    '${MaterialLocalizations.of(context).formatMediumDate(date)} / ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}';

class EventThumbnail extends StatefulWidget {
  const EventThumbnail({
    super.key,
    required this.repository,
    required this.item,
    this.size = 56,
  });
  final CustomerPublicRepository repository;
  final JsonMap item;
  final double size;
  @override
  State<EventThumbnail> createState() => _EventThumbnailState();
}

class _EventThumbnailState extends State<EventThumbnail> {
  Future<String>? future;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant EventThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) load();
  }

  void load() {
    final media = widget.item['media_paths'] ?? widget.item['portfolio_media'];
    final path = media is List && media.isNotEmpty
        ? media.first.toString()
        : '';
    future = path.isEmpty
        ? null
        : path.startsWith('https://')
        ? Future.value(path)
        : widget.repository.eventMediaUrl(path);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: ColoredBox(
        color: const Color(0xffedf4ef),
        child: FutureBuilder<String>(
          future: future,
          builder: (context, snapshot) => snapshot.hasData
              ? Image.network(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const Icon(
                    Icons.event_outlined,
                    color: Color(0xff087443),
                  ),
                )
              : const Icon(Icons.event_outlined, color: Color(0xff087443)),
        ),
      ),
    ),
  );
}
