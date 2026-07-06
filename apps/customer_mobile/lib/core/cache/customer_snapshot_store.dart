import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;

class CustomerSnapshotStore {
  CustomerSnapshotStore._();

  static const String _categoriesKey = "customer_cache_categories_v1";
  static const String _homePrefix = "customer_cache_home_v1|";
  static const String _listingPrefix = "customer_cache_listing_v1|";
  static const String _listingDetailPrefix =
      "customer_cache_listing_detail_v1|";
  static const String _contactAccessPrefix = "customer_cache_contact_v1|";

  static bool _initialized = false;
  static List<JsonMap> _categories = <JsonMap>[];
  static final Map<String, List<JsonMap>> _homeFeeds =
      <String, List<JsonMap>>{};
  static final Map<String, List<JsonMap>> _publicListings =
      <String, List<JsonMap>>{};
  static final Map<String, JsonMap> _listingDetails = <String, JsonMap>{};
  static final Map<String, JsonMap> _contactAccess = <String, JsonMap>{};

  static Future<void> initialize([SharedPreferences? sharedPreferences]) async {
    if (_initialized) {
      return;
    }
    final SharedPreferences prefs =
        sharedPreferences ?? await SharedPreferences.getInstance();
    _categories = _decodeList(prefs.getString(_categoriesKey));

    for (final String key in prefs.getKeys()) {
      if (key.startsWith(_homePrefix)) {
        _homeFeeds[key.substring(_homePrefix.length)] = _decodeList(
          prefs.getString(key),
        );
      } else if (key.startsWith(_listingPrefix)) {
        _publicListings[key.substring(_listingPrefix.length)] = _decodeList(
          prefs.getString(key),
        );
      } else if (key.startsWith(_listingDetailPrefix)) {
        final JsonMap? decoded = _decodeMap(prefs.getString(key));
        if (decoded != null) {
          _listingDetails[key.substring(_listingDetailPrefix.length)] = decoded;
        }
      } else if (key.startsWith(_contactAccessPrefix)) {
        final JsonMap? decoded = _decodeMap(prefs.getString(key));
        if (decoded != null) {
          _contactAccess[key.substring(_contactAccessPrefix.length)] = decoded;
        }
      }
    }
    _initialized = true;
  }

  static List<JsonMap> get categories =>
      List<JsonMap>.unmodifiable(_categories);

  static Future<void> saveCategories(List<JsonMap> categories) async {
    _categories = List<JsonMap>.from(categories);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_categoriesKey, jsonEncode(_categories));
  }

  static String buildScopedKey({
    String scope = "",
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
    double? latitude,
    double? longitude,
  }) {
    final String lat = latitude == null ? "" : latitude.toStringAsFixed(3);
    final String lon = longitude == null ? "" : longitude.toStringAsFixed(3);
    return [
      scope,
      regionId ?? "",
      districtId ?? "",
      wardId ?? "",
      areaId ?? "",
      lat,
      lon,
    ].join("|");
  }

  static List<JsonMap>? homeFeedForKey(String key) => _homeFeeds[key];

  static Future<void> saveHomeFeed(String key, List<JsonMap> items) async {
    _homeFeeds[key] = List<JsonMap>.from(items);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("$_homePrefix$key", jsonEncode(items));
  }

  static List<JsonMap>? publicListingsForKey(String key) =>
      _publicListings[key];

  static Future<void> savePublicListings(
    String key,
    List<JsonMap> items,
  ) async {
    _publicListings[key] = List<JsonMap>.from(items);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("$_listingPrefix$key", jsonEncode(items));
  }

  static JsonMap? listingDetailForId(String listingId) =>
      _listingDetails[listingId];

  static Future<void> saveListingDetail(String listingId, JsonMap data) async {
    _listingDetails[listingId] = Map<String, dynamic>.from(data);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      "$_listingDetailPrefix$listingId",
      jsonEncode(_listingDetails[listingId]),
    );
  }

  static Future<void> clearListingDetail(String listingId) async {
    _listingDetails.remove(listingId);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove("$_listingDetailPrefix$listingId");
  }

  static JsonMap? contactAccessForListing(String listingId) =>
      _contactAccess[listingId];

  static Future<void> saveContactAccess(String listingId, JsonMap data) async {
    _contactAccess[listingId] = Map<String, dynamic>.from(data);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("$_contactAccessPrefix$listingId", jsonEncode(data));
  }

  static Future<void> clearContactAccess(String listingId) async {
    _contactAccess.remove(listingId);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove("$_contactAccessPrefix$listingId");
  }

  static List<JsonMap> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <JsonMap>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((dynamic item) => (item as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return <JsonMap>[];
    }
  }

  static JsonMap? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}
