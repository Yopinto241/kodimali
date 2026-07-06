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
    "nav.apartments": "Apartments",
    "nav.houses": "Houses",
    "nav.cars": "Cars",
    "nav.search": "Search",
    "nav.categories": "Categories",
    "hero.tagline":
        "Find verified houses, vehicles, halls, offices, and other rentable assets around you.",
    "hero.useLocation": "Use my location",
    "hero.chooseArea": "Choose area",
    "hero.browseApartments": "Browse apartments",
    "hero.browseHouses": "Browse houses",
    "hero.browseCars": "Browse cars",
    "hero.language": "Language",
    "banner.title": "Looking for rental assets close to you?",
    "banner.skip": "Skip",
    "heading.categories": "Categories",
    "heading.browseCategories": "Browse categories",
    "feed.nearYou": "Near you",
    "feed.apartments": "Apartments",
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
    "popular.houses.subtitle": "Standalone homes and family rentals.",
    "popular.apartments.title": "Apartments",
    "popular.apartments.subtitle":
        "Serviced stays, flats, and short-stay homes ready for booking.",
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
    "agent.unlockCta": "Unlock phone number",
    "agent.unlockTitle": "Unlock agent phone",
    "agent.unlockBody":
        "Pay once through ClickPesa to reveal this agent contact on this device.",
    "agent.paymentName": "Full name",
    "agent.paymentPhone": "Phone number",
    "agent.paymentContinue": "Pay and unlock number",
    "agent.paymentCheck": "Check payment now",
    "agent.paymentAmount": "Amount: {amount} {currency}",
    "agent.paymentStarted":
        "Payment request sent. Confirm it on your phone. This screen will unlock the number automatically once ClickPesa confirms payment.",
    "agent.paymentMethod": "Payment method: {method}",
    "agent.paymentPromptTo":
        "Payment prompt sent to {phone}. Enter your mobile money PIN on that phone to finish.",
    "agent.phoneVisible": "Phone number",
    "agent.locationUnknown": "Location not shared yet",
    "agent.verified": "Verified agent",
    "agent.unverified": "Verification pending",
    "help.title": "Help",
    "help.bubble": "Help",
    "help.introTitle": "How Kodimali works",
    "help.introBody":
        "Use Kodimali to browse rental listings, choose a location, open listing details, and contact agents quickly when you are ready.",
    "help.paymentTitle": "Why payment is needed",
    "help.paymentBody":
        "Many people send requests to agents or dalali, so a request can take time before they respond. Paying to unlock the phone number helps you call the agent directly when you need a faster response.",
    "help.paymentHowTitle": "How payment is made",
    "help.paymentHowBody":
        "Open a listing, tap unlock phone number, enter your details, then confirm the mobile money payment prompt on your phone. Once ClickPesa confirms payment, the number appears automatically in the app.",
    "help.platformTitle": "Platform support",
    "help.platformBody":
        "The app is currently supported on Android. iOS support is coming soon. For now, iOS users can use the Kodimali website.",
    "help.supportTitle": "Get more help",
    "help.supportBody":
        "Contact us on WhatsApp or call us directly if you need help using the app or completing a payment.",
    "help.whatsappOne": "WhatsApp 0684684972",
    "help.callOne": "Call 0684684972",
    "help.whatsappTwo": "WhatsApp 0628621737",
    "help.callTwo": "Call 0628621737",
    "help.socialTitle": "Find us online",
    "help.socialBody":
        "You can also find us on Instagram and Facebook for updates and support.",
    "help.instagram": "Instagram @kodimali1",
    "help.facebook": "Facebook Kodimali Tanzania",
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
    "request.email": "Email address",
    "request.phone": "Phone number / WhatsApp",
    "request.phoneOptional": "Phone number / WhatsApp (optional)",
    "request.checkIn": "Check-in date",
    "request.checkOut": "Check-out date",
    "request.guestCount": "Guests (optional)",
    "request.message": "Message (optional)",
    "request.services": "Services to confirm",
    "request.submit": "Send request",
    "request.submitting": "Sending...",
    "request.nameError": "Enter a valid name.",
    "request.emailError": "Enter a valid email address.",
    "request.phoneError": "Enter a valid phone number.",
    "request.dateError": "Choose valid check-in and check-out dates.",
    "request.successTitle": "Your request was sent to the agent.",
    "request.successBody":
        "The agent will reply by email or phone to confirm availability.",
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
    "apartment.servicesTitle": "Available services",
    "apartment.bookingTitle": "Book this apartment",
    "apartment.bookingBody":
        "Choose your stay dates, leave your email, and select the services you want the agent to confirm.",
    "apartment.service.wifi": "WiFi",
    "apartment.service.food": "Food",
    "apartment.service.transport": "Transport",
    "apartment.service.cleaning": "Cleaning",
    "apartment.service.laundry": "Laundry",
  },
  "sw": <String, String>{
    "lang.en": "Kiingereza",
    "lang.sw": "Kiswahili",
    "nav.home": "Nyumbani",
    "nav.apartments": "Apartment",
    "nav.houses": "Nyumba",
    "nav.cars": "Magari",
    "nav.search": "Tafuta",
    "nav.categories": "Makundi",
    "hero.tagline":
        "Pata nyumba, magari, kumbi, ofisi, na mali nyingine za kukodisha kutoka kwa mawakala waliothibitishwa.",
    "hero.useLocation": "Tumia eneo langu",
    "hero.chooseArea": "Chagua eneo",
    "hero.browseApartments": "Angalia apartment",
    "hero.browseHouses": "Angalia nyumba",
    "hero.browseCars": "Angalia magari",
    "hero.language": "Lugha",
    "banner.title": "Unatafuta mali za kukodisha karibu na ulipo?",
    "banner.skip": "Ruka",
    "heading.categories": "Makundi",
    "heading.browseCategories": "Angalia makundi",
    "feed.nearYou": "Karibu na wewe",
    "feed.apartments": "Apartment",
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
    "popular.houses.subtitle":
        "Nyumba za familia na upangishaji wa muda mrefu.",
    "popular.apartments.title": "Apartment",
    "popular.apartments.subtitle":
        "Apartment za kukaa, short stay, na serviced stays tayari kwa booking.",
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
    "agent.unlockCta": "Fungua namba ya simu",
    "agent.unlockTitle": "Fungua simu ya wakala",
    "agent.unlockBody":
        "Lipa mara moja kupitia ClickPesa ili kuona namba ya wakala huyu kwenye kifaa hiki.",
    "agent.paymentName": "Jina kamili",
    "agent.paymentPhone": "Namba ya simu",
    "agent.paymentContinue": "Lipa na fungua namba",
    "agent.paymentCheck": "Angalia hali ya malipo",
    "agent.paymentAmount": "Kiasi: {amount} {currency}",
    "agent.paymentStarted":
        "Ombi la malipo limetumwa. Thibitisha kwenye simu yako. Skrini hii itafungua namba moja kwa moja ClickPesa ikishathibitisha malipo.",
    "agent.paymentMethod": "Njia ya malipo: {method}",
    "agent.paymentPromptTo":
        "Ombi la malipo limetumwa kwenda {phone}. Weka PIN ya huduma ya fedha ya simu kwenye simu hiyo kumalizia.",
    "agent.phoneVisible": "Namba ya simu",
    "agent.locationUnknown": "Eneo bado halijawekwa",
    "agent.verified": "Wakala aliyethibitishwa",
    "agent.unverified": "Uthibitisho bado",
    "help.title": "Msaada",
    "help.bubble": "Msaada",
    "help.introTitle": "Jinsi ya kutumia Kodimali",
    "help.introBody":
        "Tumia Kodimali kuangalia listings za kupangisha, kuchagua eneo, kufungua maelezo ya listing, na kuwasiliana na wakala haraka unapokuwa tayari.",
    "help.paymentTitle": "Kwa nini malipo yanahitajika",
    "help.paymentBody":
        "Watu wengi hutuma maombi kwa agent au dalali, hivyo ombi linaweza kuchukua muda kabla hawajajibu. Kulipia kufungua namba ya simu hukusaidia kumpigia wakala moja kwa moja unapohitaji majibu ya haraka.",
    "help.paymentHowTitle": "Jinsi malipo yanavyofanyika",
    "help.paymentHowBody":
        "Fungua listing, bonyeza kufungua namba ya simu, weka taarifa zako, kisha thibitisha ombi la malipo ya simu litakalofika kwenye namba yako. ClickPesa ikishathibitisha malipo, namba itaonekana moja kwa moja ndani ya app.",
    "help.platformTitle": "Mifumo inayotumika",
    "help.platformBody":
        "Kwa sasa app inatumika kwenye Android. Msaada wa iOS unakuja hivi karibuni. Kwa sasa watumiaji wa iOS wanaweza kutumia tovuti ya Kodimali.",
    "help.supportTitle": "Pata msaada zaidi",
    "help.supportBody":
        "Wasiliana nasi kupitia WhatsApp au piga simu moja kwa moja kama unahitaji msaada wa kutumia app au kukamilisha malipo.",
    "help.whatsappOne": "WhatsApp 0684684972",
    "help.callOne": "Piga 0684684972",
    "help.whatsappTwo": "WhatsApp 0628621737",
    "help.callTwo": "Piga 0628621737",
    "help.socialTitle": "Tupate mtandaoni",
    "help.socialBody":
        "Unaweza pia kutupata kwenye Instagram na Facebook kwa updates na msaada.",
    "help.instagram": "Instagram @kodimali1",
    "help.facebook": "Facebook Kodimali Tanzania",
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
    "request.email": "Barua pepe",
    "request.phone": "Namba ya simu / WhatsApp",
    "request.phoneOptional": "Namba ya simu / WhatsApp (si lazima)",
    "request.checkIn": "Tarehe ya kuingia",
    "request.checkOut": "Tarehe ya kutoka",
    "request.guestCount": "Idadi ya wageni (si lazima)",
    "request.message": "Ujumbe (si lazima)",
    "request.services": "Huduma za kuthibitisha",
    "request.submit": "Tuma Ombi",
    "request.submitting": "Inatuma...",
    "request.nameError": "Weka jina sahihi.",
    "request.emailError": "Weka barua pepe sahihi.",
    "request.phoneError": "Weka namba sahihi.",
    "request.dateError": "Chagua tarehe sahihi za kuingia na kutoka.",
    "request.successTitle": "Ombi lako limetumwa kwa wakala.",
    "request.successBody":
        "Wakala atakujibu kwa email au simu kuthibitisha upatikanaji.",
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
    "apartment.servicesTitle": "Huduma zinazopatikana",
    "apartment.bookingTitle": "Book apartment hii",
    "apartment.bookingBody":
        "Chagua tarehe za kukaa, acha email yako, na chagua huduma unazotaka wakala athibitishe.",
    "apartment.service.wifi": "WiFi",
    "apartment.service.food": "Chakula",
    "apartment.service.transport": "Usafiri",
    "apartment.service.cleaning": "Usafi",
    "apartment.service.laundry": "Dobi",
  },
};
