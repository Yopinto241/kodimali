import 'package:flutter/material.dart';

class CustomerAppScope extends InheritedWidget {
  const CustomerAppScope({
    super.key,
    required this.languageCode,
    required this.onLanguageChanged,
    required super.child,
  });

  final String languageCode;
  final Future<void> Function(String languageCode) onLanguageChanged;

  static CustomerAppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomerAppScope>();

  @override
  bool updateShouldNotify(CustomerAppScope oldWidget) =>
      languageCode != oldWidget.languageCode;
}

extension CustomerLocalizationX on BuildContext {
  CustomerAppScope? get _customerScope => CustomerAppScope.maybeOf(this);

  String get languageCode => _customerScope?.languageCode ?? "en";

  bool get isSwahili => languageCode == "sw";

  Future<void> setLanguageCode(String nextLanguageCode) =>
      _customerScope?.onLanguageChanged(nextLanguageCode) ??
      Future<void>.value();

  String tr(
    String key, {
    Map<String, String> values = const <String, String>{},
  }) {
    final Map<String, String> selected =
        _localizedStrings[languageCode] ?? _localizedStrings["en"]!;
    String text = selected[key] ?? _localizedStrings["en"]![key] ?? key;
    for (final MapEntry<String, String> entry in values.entries) {
      text = text.replaceAll("{${entry.key}}", entry.value);
    }
    return text;
  }
}

const Map<String, Map<String, String>>
_localizedStrings = <String, Map<String, String>>{
  "en": <String, String>{
    "lang.en": "English",
    "lang.sw": "Swahili",
    "nav.home": "Home",
    "nav.houses": "Houses",
    "nav.cars": "Cars",
    "nav.search": "Search",
    "nav.categories": "Categories",
    "hero.tagline":
        "Find verified houses, vehicles, halls, offices, and other rentable assets around you.",
    "hero.useLocation": "Use my location",
    "hero.chooseArea": "Choose area",
    "hero.browseHouses": "Browse houses",
    "hero.browseCars": "Browse cars",
    "hero.language": "Language",
    "banner.title": "Looking for rental assets close to you?",
    "banner.skip": "Skip",
    "heading.categories": "Categories",
    "heading.browseCategories": "Browse categories",
    "feed.nearYou": "Near you",
    "feed.houses": "Rental houses",
    "feed.cars": "Cars and motorcycles",
    "feed.offices": "Offices and halls",
    "feed.other": "Other listings",
    "search.label": "Search listings",
    "search.empty": "No listings were found.",
    "search.emptyQuery": "No listings matched \"{query}\".",
    "search.searching": "Searching listings...",
    "search.searchingQuery": "Searching for \"{query}\"...",
    "search.resultCount": "{count} listings found",
    "search.resultCountQuery": "{count} listings found for \"{query}\"",
    "search.suggestions": "Suggested listings",
    "search.liveHint": "Results update while you type.",
    "search.suggestionsHint":
        "Tap a suggestion or keep scrolling through results.",
    "search.tryAnother": "Try another word, category, or location.",
    "search.clear": "Clear search",
    "popular.houses.title": "Houses",
    "popular.houses.subtitle": "Homes and apartments people ask for most.",
    "popular.cars.title": "Cars",
    "popular.cars.subtitle":
        "Popular vehicle rentals ready for immediate requests.",
    "category.empty": "No listings are available in this category yet.",
    "category.error": "This category could not load right now.",
    "category.titleFallback": "Category",
    "category.browseTitle": "Explore this category",
    "category.browseBody":
        "Fresh public listings, clear photos, and quick request access in one place.",
    "category.related": "More public listings",
    "category.tryOthers":
        "There are no live listings in this category yet, but you can keep browsing other active listings below.",
    "listing.public": "Verified public listing",
    "listing.open": "Open listing",
    "listing.view": "View",
    "listing.expandCover": "Expand photo",
    "listing.hint":
        "Swipe through details, open media fullscreen, and send a quick request when ready.",
    "listing.details": "Listing details",
    "listing.media": "Media",
    "listing.tapExpand": "Tap to expand",
    "listing.tapMediaHint":
        "Tap any photo to open it clearly in fullscreen. Videos start playing automatically.",
    "listing.additionalDetails": "Details",
    "listing.request": "Send request",
    "listing.notFound": "Listing not found",
    "agent.title": "Agent details",
    "agent.phoneHidden":
        "Phone number hidden. Pay to unlock this agent contact.",
    "agent.locationUnknown": "Location not shared yet",
    "agent.verified": "Verified agent",
    "agent.unverified": "Verification pending",
    "detail.available": "Available",
    "detail.unavailable": "Not available",
    "detail.included": "Included",
    "detail.notIncluded": "Not included",
    "detail.furnishedYes": "Furnished",
    "detail.furnishedNo": "Not furnished",
    "promotion.titleFallback": "Sponsored update",
    "promotion.label": "Sponsored",
    "request.form": "Request form",
    "request.fullName": "Full name",
    "request.phone": "Phone number / WhatsApp",
    "request.submit": "Send request",
    "request.submitting": "Sending...",
    "request.nameError": "Enter a valid name.",
    "request.phoneError": "Enter a valid phone number.",
    "request.successTitle": "Your request was sent to the agent.",
    "request.successBody":
        "The agent will call or WhatsApp you to confirm availability.",
    "request.reference": "Reference: {reference}",
    "request.backHome": "Back home",
    "location.region": "Region",
    "location.district": "District",
    "location.ward": "Ward",
    "location.area": "Area",
    "location.useThis": "Use this location",
    "location.chooseOptional": "Optional",
    "location.clearDistrict": "Use region only",
    "location.clearWard": "Use district only",
    "location.clearArea": "Use ward only",
    "location.retry": "Retry",
    "location.failed": "We could not load locations right now.",
    "media.autoplay": "Autoplay video",
    "media.tapToPlay": "Tap to play video",
    "media.loading": "Loading media...",
    "farm.highlights": "Farm highlights",
    "farm.water": "Water availability",
    "farm.crops": "Best crops",
    "farm.size": "Land size",
  },
  "sw": <String, String>{
    "lang.en": "Kiingereza",
    "lang.sw": "Kiswahili",
    "nav.home": "Nyumbani",
    "nav.houses": "Nyumba",
    "nav.cars": "Magari",
    "nav.search": "Tafuta",
    "nav.categories": "Makundi",
    "hero.tagline":
        "Pata nyumba, magari, kumbi, ofisi, na mali nyingine za kukodisha kutoka kwa mawakala waliothibitishwa.",
    "hero.useLocation": "Tumia eneo langu",
    "hero.chooseArea": "Chagua eneo",
    "hero.browseHouses": "Angalia nyumba",
    "hero.browseCars": "Angalia magari",
    "hero.language": "Lugha",
    "banner.title": "Unatafuta mali za kukodisha karibu na ulipo?",
    "banner.skip": "Ruka",
    "heading.categories": "Makundi",
    "heading.browseCategories": "Angalia makundi",
    "feed.nearYou": "Karibu na wewe",
    "feed.houses": "Nyumba za kupangisha",
    "feed.cars": "Magari na pikipiki",
    "feed.offices": "Ofisi na kumbi",
    "feed.other": "Matangazo mengine",
    "search.label": "Tafuta matangazo",
    "search.empty": "Hakuna listings zilizopatikana.",
    "search.emptyQuery": "Hakuna listings zilizolingana na \"{query}\".",
    "search.searching": "Inatafuta listings...",
    "search.searchingQuery": "Inatafuta \"{query}\"...",
    "search.resultCount": "Listings {count} zimepatikana",
    "search.resultCountQuery": "Listings {count} zimepatikana kwa \"{query}\"",
    "search.suggestions": "Mapendekezo ya listings",
    "search.liveHint": "Matokeo yanabadilika unapoandika.",
    "search.suggestionsHint":
        "Gusa pendekezo au endelea kushuka kuona matokeo yote.",
    "search.tryAnother": "Jaribu neno, category, au eneo jingine.",
    "search.clear": "Futa utafutaji",
    "popular.houses.title": "Nyumba",
    "popular.houses.subtitle": "Nyumba na apartment zinazotafutwa zaidi.",
    "popular.cars.title": "Magari",
    "popular.cars.subtitle":
        "Magari ya kukodisha yanayopatikana kwa maombi ya haraka.",
    "category.empty": "Hakuna listings kwenye category hii.",
    "category.error": "Category hii haikupakia kwa sasa.",
    "category.titleFallback": "Category",
    "category.browseTitle": "Chunguza category hii",
    "category.browseBody":
        "Listings za umma, picha zilizo wazi, na kutuma ombi kwa haraka sehemu moja.",
    "category.related": "Listings nyingine za umma",
    "category.tryOthers":
        "Bado hakuna listings hai kwenye category hii, lakini unaweza kuendelea kuona listings nyingine hapa chini.",
    "listing.public": "Tangazo la umma lililothibitishwa",
    "listing.open": "Fungua listing",
    "listing.view": "View",
    "listing.expandCover": "Fungua picha",
    "listing.hint":
        "Tembea kwenye maelezo, fungua picha vizuri, na tuma ombi haraka ukiwa tayari.",
    "listing.details": "Maelezo ya listing",
    "listing.media": "Media",
    "listing.tapExpand": "Bonyeza kufungua",
    "listing.tapMediaHint":
        "Bonyeza picha kuiona vizuri. Video zinaanza kucheza zenyewe.",
    "listing.additionalDetails": "Maelezo",
    "listing.request": "Tuma Ombi",
    "listing.notFound": "Listing haikupatikana",
    "agent.title": "Maelezo ya wakala",
    "agent.phoneHidden":
        "Namba ya simu imefichwa. Lipa ili kuona mawasiliano ya wakala huyu.",
    "agent.locationUnknown": "Eneo bado halijawekwa",
    "agent.verified": "Wakala aliyethibitishwa",
    "agent.unverified": "Uthibitisho bado",
    "detail.available": "Inapatikana",
    "detail.unavailable": "Haipatikani",
    "detail.included": "Imejumuishwa",
    "detail.notIncluded": "Haijajumuishwa",
    "detail.furnishedYes": "Ina fanicha",
    "detail.furnishedNo": "Haina fanicha",
    "promotion.titleFallback": "Sponsored update",
    "promotion.label": "Sponsored",
    "request.form": "Fomu ya ombi",
    "request.fullName": "Jina kamili",
    "request.phone": "Namba ya simu / WhatsApp",
    "request.submit": "Tuma Ombi",
    "request.submitting": "Inatuma...",
    "request.nameError": "Weka jina sahihi.",
    "request.phoneError": "Weka namba sahihi.",
    "request.successTitle": "Ombi lako limetumwa kwa wakala.",
    "request.successBody":
        "Wakala atakupigia au kukutumia WhatsApp kuthibitisha upatikanaji.",
    "request.reference": "Reference: {reference}",
    "request.backHome": "Rudi Home",
    "location.region": "Region",
    "location.district": "District",
    "location.ward": "Ward",
    "location.area": "Area",
    "location.useThis": "Tumia eneo hili",
    "location.chooseOptional": "Si lazima",
    "location.clearDistrict": "Tumia region tu",
    "location.clearWard": "Tumia district tu",
    "location.clearArea": "Tumia ward tu",
    "location.retry": "Jaribu tena",
    "location.failed": "Hatukuweza kupakia maeneo kwa sasa.",
    "media.autoplay": "Video ya kujiendesha",
    "media.tapToPlay": "Gusa kucheza video",
    "media.loading": "Inapakia media...",
    "farm.highlights": "Vipengele vya shamba",
    "farm.water": "Upatikanaji wa maji",
    "farm.crops": "Mazao bora",
    "farm.size": "Ukubwa wa ardhi",
  },
};
