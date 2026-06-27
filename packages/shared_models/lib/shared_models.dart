enum AppRole { customer, agent, admin }

enum ListingCategory {
  house,
  car,
  motorcycle,
  office,
  meetingHall,
  ceremonyHall,
  equipment,
  otherAsset,
}

extension ListingCategoryX on ListingCategory {
  String get storageValue => switch (this) {
    ListingCategory.house => "house",
    ListingCategory.car => "car",
    ListingCategory.motorcycle => "motorcycle",
    ListingCategory.office => "office",
    ListingCategory.meetingHall => "meeting_hall",
    ListingCategory.ceremonyHall => "ceremony_hall",
    ListingCategory.equipment => "equipment",
    ListingCategory.otherAsset => "other_asset",
  };

  String get displayName => switch (this) {
    ListingCategory.house => "House",
    ListingCategory.car => "Car",
    ListingCategory.motorcycle => "Motorcycle",
    ListingCategory.office => "Office",
    ListingCategory.meetingHall => "Meeting Hall",
    ListingCategory.ceremonyHall => "Ceremony Hall",
    ListingCategory.equipment => "Equipment",
    ListingCategory.otherAsset => "Other Asset",
  };
}

enum PricePeriod { hour, day, week, month, year }

extension PricePeriodX on PricePeriod {
  String get storageValue => switch (this) {
    PricePeriod.hour => "hour",
    PricePeriod.day => "day",
    PricePeriod.week => "week",
    PricePeriod.month => "month",
    PricePeriod.year => "year",
  };

  String get label => switch (this) {
    PricePeriod.hour => "Per hour",
    PricePeriod.day => "Per day",
    PricePeriod.week => "Per week",
    PricePeriod.month => "Per month",
    PricePeriod.year => "Per year",
  };
}

enum MediaType { image, video }

extension MediaTypeX on MediaType {
  String get storageValue => switch (this) {
    MediaType.image => "image",
    MediaType.video => "video",
  };
}

enum LocationType { country, region, district, ward, area, street }

extension LocationTypeX on LocationType {
  String get storageValue => switch (this) {
    LocationType.country => "country",
    LocationType.region => "region",
    LocationType.district => "district",
    LocationType.ward => "ward",
    LocationType.area => "area",
    LocationType.street => "street",
  };
}

enum BookingStatus {
  newRequest,
  checkingAvailability,
  contacted,
  viewingScheduled,
  reserved,
  confirmed,
  completed,
  cancelled,
  rejected,
  noResponse,
  agentDelayed,
}

extension BookingStatusX on BookingStatus {
  String get storageValue => switch (this) {
    BookingStatus.newRequest => "new",
    BookingStatus.checkingAvailability => "checking_availability",
    BookingStatus.contacted => "contacted",
    BookingStatus.viewingScheduled => "viewing_scheduled",
    BookingStatus.reserved => "reserved",
    BookingStatus.confirmed => "confirmed",
    BookingStatus.completed => "completed",
    BookingStatus.cancelled => "cancelled",
    BookingStatus.rejected => "rejected",
    BookingStatus.noResponse => "no_response",
    BookingStatus.agentDelayed => "agent_delayed",
  };

  String get label => switch (this) {
    BookingStatus.newRequest => "New",
    BookingStatus.checkingAvailability => "Checking Availability",
    BookingStatus.contacted => "Contacted",
    BookingStatus.viewingScheduled => "Viewing Scheduled",
    BookingStatus.reserved => "Reserved",
    BookingStatus.confirmed => "Confirmed",
    BookingStatus.completed => "Completed",
    BookingStatus.cancelled => "Cancelled",
    BookingStatus.rejected => "Rejected",
    BookingStatus.noResponse => "No Response",
    BookingStatus.agentDelayed => "Agent Delayed",
  };
}

class ListingSummary {
  const ListingSummary({
    required this.title,
    required this.category,
    required this.publicLocationLabel,
    required this.priceLabel,
    required this.agentName,
    required this.availabilityLabel,
  });

  final String title;
  final ListingCategory category;
  final String publicLocationLabel;
  final String priceLabel;
  final String agentName;
  final String availabilityLabel;
}

class WorkflowStage {
  const WorkflowStage({required this.title, required this.description});

  final String title;
  final String description;
}
