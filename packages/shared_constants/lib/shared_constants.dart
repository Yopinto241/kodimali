import 'package:shared_models/shared_models.dart';

const String appName = 'KODIMALI';
const String appTagline =
    'Mali halisi. Wakala aliyethibitishwa. Booking salama.';
const String mvpLaunchCity = 'Arusha';

const List<String> supportedLanguages = <String>['sw', 'en'];

class CategoryLabel {
  const CategoryLabel({
    required this.category,
    required this.swahili,
    required this.english,
  });

  final ListingCategory category;
  final String swahili;
  final String english;
}

class MediaLimitRule {
  const MediaLimitRule({required this.label, required this.value});

  final String label;
  final String value;
}

const List<CategoryLabel> mvpCategories = <CategoryLabel>[
  CategoryLabel(
    category: ListingCategory.house,
    swahili: 'Nyumba',
    english: 'Houses',
  ),
  CategoryLabel(
    category: ListingCategory.car,
    swahili: 'Magari',
    english: 'Cars',
  ),
  CategoryLabel(
    category: ListingCategory.motorcycle,
    swahili: 'Pikipiki',
    english: 'Motorcycles',
  ),
  CategoryLabel(
    category: ListingCategory.office,
    swahili: 'Ofisi',
    english: 'Offices',
  ),
  CategoryLabel(
    category: ListingCategory.meetingHall,
    swahili: 'Kumbi za mikutano',
    english: 'Meeting halls',
  ),
  CategoryLabel(
    category: ListingCategory.ceremonyHall,
    swahili: 'Kumbi za sherehe',
    english: 'Ceremony halls',
  ),
];

const List<String> postingFlow = <String>[
  'Choose asset category',
  'Add basic information',
  'Select location',
  'Add price and availability',
  'Upload media',
  'Add owner record',
  'Submit for approval',
];

const List<LocationType> locationHierarchy = <LocationType>[
  LocationType.region,
  LocationType.district,
  LocationType.ward,
  LocationType.area,
];

const List<BookingStatus> bookingTimeline = <BookingStatus>[
  BookingStatus.newRequest,
  BookingStatus.checkingAvailability,
  BookingStatus.contacted,
  BookingStatus.viewingScheduled,
  BookingStatus.reserved,
  BookingStatus.confirmed,
  BookingStatus.completed,
  BookingStatus.cancelled,
  BookingStatus.rejected,
  BookingStatus.noResponse,
  BookingStatus.agentDelayed,
];

const List<PricePeriod> pricePeriods = <PricePeriod>[
  PricePeriod.hour,
  PricePeriod.day,
  PricePeriod.week,
  PricePeriod.month,
  PricePeriod.year,
];

const List<MediaLimitRule> mediaLimits = <MediaLimitRule>[
  MediaLimitRule(label: 'Maximum images', value: '8'),
  MediaLimitRule(label: 'Maximum video files', value: '1'),
  MediaLimitRule(label: 'Maximum video length', value: '30 seconds'),
  MediaLimitRule(label: 'Maximum video size', value: '30 MB'),
];
