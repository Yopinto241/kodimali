import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../cache/customer_snapshot_store.dart';

typedef JsonMap = Map<String, dynamic>;

class CustomerPublicRepository {
  CustomerPublicRepository(this._client);

  final SupabaseClient _client;
  static const String _agentPhotoBucket = "agent-profile-photos";
  static const int _listingMediaSignedUrlSeconds = 3600;
  static const int _promotionMediaSignedUrlSeconds = 3600;
  static const Duration _categoryCacheTtl = Duration(minutes: 30);
  static const Duration _promotionCacheTtl = Duration(minutes: 5);
  static const Duration _feedCacheTtl = Duration(minutes: 2);
  static final Map<String, _SignedUrlCacheEntry> _listingMediaUrlCache =
      <String, _SignedUrlCacheEntry>{};
  static final Map<String, _SignedUrlCacheEntry> _promotionMediaUrlCache =
      <String, _SignedUrlCacheEntry>{};
  static _ListCacheEntry<JsonMap>? _categoriesCache;
  static final Map<String, _ListCacheEntry<JsonMap>> _promotionsCache =
      <String, _ListCacheEntry<JsonMap>>{};
  static final Map<String, _ListCacheEntry<JsonMap>> _homeFeedCache =
      <String, _ListCacheEntry<JsonMap>>{};
  static final Map<String, _ListCacheEntry<JsonMap>> _publicListingsCache =
      <String, _ListCacheEntry<JsonMap>>{};

  void invalidatePublicDataCache({bool includeCategories = false}) {
    _homeFeedCache.clear();
    _publicListingsCache.clear();
    _promotionsCache.clear();
    if (includeCategories) {
      _categoriesCache = null;
    }
  }

  Future<List<JsonMap>> fetchCategories() async {
    final _ListCacheEntry<JsonMap>? cached = _categoriesCache;
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.items;
    }
    final List<JsonMap> categories = (await _client
            .from("asset_categories")
            .select(
              "id, name, slug, description, icon_key, display_order, home_feed_weight",
            )
            .eq("is_active", true)
            .order("display_order")
            .order("name"))
        .cast<JsonMap>();
    _categoriesCache = _ListCacheEntry<JsonMap>(
      items: categories,
      expiresAt: DateTime.now().add(_categoryCacheTtl),
    );
    unawaited(CustomerSnapshotStore.saveCategories(categories));
    return categories;
  }

  Future<List<JsonMap>> fetchHomeFeed({
    int limit = 20,
    int page = 0,
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
    double? latitude,
    double? longitude,
    String? sessionSeed,
  }) async {
    final String cacheKey = [
      limit,
      page,
      regionId ?? "",
      districtId ?? "",
      wardId ?? "",
      areaId ?? "",
      latitude?.toStringAsFixed(4) ?? "",
      longitude?.toStringAsFixed(4) ?? "",
      sessionSeed ?? "",
    ].join("|");
    final _ListCacheEntry<JsonMap>? cached = _homeFeedCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.items;
    }
    final List<JsonMap> rows = await _fetchHomeFeedRows(
      limit: limit,
      page: page,
      regionId: regionId,
      districtId: districtId,
      wardId: wardId,
      areaId: areaId,
      latitude: latitude,
      longitude: longitude,
      sessionSeed: sessionSeed,
    );
    final List<JsonMap> feed = await Future.wait(
      rows.map(
        (JsonMap row) async => <String, dynamic>{
          ...row,
          "cover_url": await _signListingMediaPath(
            row["cover_storage_path"] as String?,
          ),
          "agent_profile_photo_url": _publicAgentPhotoUrl(
            row["agent_profile_photo_path"] as String?,
          ),
        },
      ),
    );
    _homeFeedCache[cacheKey] = _ListCacheEntry<JsonMap>(
      items: feed,
      expiresAt: DateTime.now().add(_feedCacheTtl),
    );
    if (page == 0) {
      final String snapshotKey = CustomerSnapshotStore.buildScopedKey(
        scope: "home",
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: areaId,
        latitude: latitude,
        longitude: longitude,
      );
      unawaited(CustomerSnapshotStore.saveHomeFeed(snapshotKey, feed));
    }
    return feed;
  }

  Future<List<JsonMap>> fetchPromotions({
    required String surface,
    String placement = "global",
    int limit = 3,
  }) async {
    final String cacheKey = "$surface|$placement|$limit";
    final _ListCacheEntry<JsonMap>? cached = _promotionsCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.items;
    }
    final List<JsonMap> rows = await _fetchPromotionRows(
      surface: surface,
      placement: placement,
      limit: limit,
    );
    final List<JsonMap> promotions = await Future.wait(
      rows.map(
        (JsonMap row) async => <String, dynamic>{
          ...row,
          "media_url": await _signPromotionMediaPath(
            row["media_path"] as String?,
          ),
          "thumbnail_url": await _signPromotionMediaPath(
            row["thumbnail_path"] as String?,
          ),
        },
      ),
    );
    _promotionsCache[cacheKey] = _ListCacheEntry<JsonMap>(
      items: promotions,
      expiresAt: DateTime.now().add(_promotionCacheTtl),
    );
    return promotions;
  }

  Future<List<JsonMap>> _fetchPromotionRows({
    required String surface,
    required String placement,
    required int limit,
  }) async {
    try {
      return (await _client.rpc(
        "get_active_platform_promotions",
        params: <String, dynamic>{
          "p_surface": surface,
          "p_placement": placement,
          "p_limit": limit,
        },
      )).cast<JsonMap>();
    } on PostgrestException catch (error) {
      if (!_isPromotionRpcCompatibilityError(error)) {
        rethrow;
      }
      return (await _client.rpc(
        "get_active_platform_promotions",
        params: <String, dynamic>{
          "p_placement": placement,
          "p_limit": limit,
        },
      )).cast<JsonMap>();
    }
  }

  Future<List<JsonMap>> fetchPublicListings({
    String? categorySlug,
    String? searchText,
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
    int limit = 20,
    int page = 0,
    double? latitude,
    double? longitude,
    String? sessionSeed,
  }) async {
    final String cacheKey = [
      categorySlug ?? "",
      searchText ?? "",
      regionId ?? "",
      districtId ?? "",
      wardId ?? "",
      areaId ?? "",
      limit,
      page,
      latitude?.toStringAsFixed(4) ?? "",
      longitude?.toStringAsFixed(4) ?? "",
      sessionSeed ?? "",
    ].join("|");
    final _ListCacheEntry<JsonMap>? cached = _publicListingsCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.items;
    }
    final List<JsonMap> rows = await _fetchPublicListingRows(
      categorySlug: categorySlug,
      searchText: searchText,
      regionId: regionId,
      districtId: districtId,
      wardId: wardId,
      areaId: areaId,
      limit: limit,
      page: page,
      latitude: latitude,
      longitude: longitude,
      sessionSeed: sessionSeed,
    );
    final List<JsonMap> listings = await Future.wait(
      rows.map(
        (JsonMap row) async => <String, dynamic>{
          ...row,
          "cover_url": await _signListingMediaPath(
            row["cover_storage_path"] as String?,
          ),
          "agent_profile_photo_url": _publicAgentPhotoUrl(
            row["agent_profile_photo_path"] as String?,
          ),
        },
      ),
    );
    _publicListingsCache[cacheKey] = _ListCacheEntry<JsonMap>(
      items: listings,
      expiresAt: DateTime.now().add(_feedCacheTtl),
    );
    if (page == 0 && (categorySlug?.isNotEmpty == true)) {
      final String snapshotKey = CustomerSnapshotStore.buildScopedKey(
        scope: categorySlug!,
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: areaId,
        latitude: latitude,
        longitude: longitude,
      );
      unawaited(CustomerSnapshotStore.savePublicListings(snapshotKey, listings));
    }
    return listings;
  }

  Future<List<JsonMap>> fetchLocations({
    required String? parentId,
    required String locationType,
  }) async {
    dynamic query = _client
        .from("locations")
        .select("id, name, location_type, parent_id")
        .eq("location_type", locationType)
        .eq("is_active", true);
    query = parentId == null
        ? query.filter("parent_id", "is", "null")
        : query.eq("parent_id", parentId);
    return (await query.order("name")).cast<JsonMap>();
  }

  Future<List<JsonMap>> _fetchHomeFeedRows({
    required int limit,
    required int page,
    required String? regionId,
    required String? districtId,
    required String? wardId,
    required String? areaId,
    required double? latitude,
    required double? longitude,
    required String? sessionSeed,
  }) async {
    try {
      return (await _client.rpc(
        "get_public_home_feed",
        params: <String, dynamic>{
          "p_limit": limit,
          "p_page": page,
          "p_selected_region_id": regionId,
          "p_selected_district_id": districtId,
          "p_selected_ward_id": wardId,
          "p_selected_area_id": areaId,
          "p_latitude": latitude,
          "p_longitude": longitude,
          "p_session_seed": sessionSeed,
        },
      )).cast<JsonMap>();
    } on PostgrestException catch (error) {
      if (!_isMissingRpcSignature(error)) {
        rethrow;
      }
      return (await _client.rpc(
        "get_public_home_feed",
        params: <String, dynamic>{
          "p_limit": limit,
          "p_page": page,
          "p_selected_region_id": regionId,
          "p_selected_district_id": districtId,
          "p_latitude": latitude,
          "p_longitude": longitude,
          "p_session_seed": sessionSeed,
        },
      )).cast<JsonMap>();
    }
  }

  Future<List<JsonMap>> _fetchPublicListingRows({
    required String? categorySlug,
    required String? searchText,
    required String? regionId,
    required String? districtId,
    required String? wardId,
    required String? areaId,
    required int limit,
    required int page,
    required double? latitude,
    required double? longitude,
    required String? sessionSeed,
  }) async {
    try {
      return (await _client.rpc(
        "get_public_listings",
        params: <String, dynamic>{
          "p_category_slug": categorySlug,
          "p_search_text": searchText,
          "p_region_id": regionId,
          "p_district_id": districtId,
          "p_ward_id": wardId,
          "p_area_id": areaId,
          "p_limit": limit,
          "p_page": page,
          "p_latitude": latitude,
          "p_longitude": longitude,
          "p_session_seed": sessionSeed,
        },
      )).cast<JsonMap>();
    } on PostgrestException catch (error) {
      if (!_isMissingRpcSignature(error)) {
        rethrow;
      }
      return (await _client.rpc(
        "get_public_listings",
        params: <String, dynamic>{
          "p_category_slug": categorySlug,
          "p_search_text": searchText,
          "p_region_id": regionId,
          "p_district_id": districtId,
          "p_limit": limit,
          "p_page": page,
          "p_latitude": latitude,
          "p_longitude": longitude,
          "p_session_seed": sessionSeed,
        },
      )).cast<JsonMap>();
    }
  }

  bool _isMissingRpcSignature(PostgrestException error) {
    return error.code == "PGRST202" ||
        error.message.contains("schema cache") ||
        error.message.contains("Could not find the function");
  }

  bool _isPromotionRpcCompatibilityError(PostgrestException error) {
    return _isMissingRpcSignature(error) ||
        error.code == "PGRST203" ||
        error.message.contains("Could not choose the best candidate function");
  }

  Future<JsonMap> fetchListingDetail(String listingId) async {
    final List<dynamic> rows = await _client.rpc(
      "get_public_listing_detail",
      params: <String, dynamic>{"p_listing_id": listingId},
    );
    if (rows.isEmpty) {
      throw StateError("Listing not found");
    }
    final JsonMap row = (rows.first as Map).cast<String, dynamic>();
    final List<dynamic> mediaRows =
        row["media"] as List<dynamic>? ?? <dynamic>[];
    final List<JsonMap> signedMedia = await Future.wait(
      mediaRows.map((dynamic item) async {
        final JsonMap media = (item as Map).cast<String, dynamic>();
        final String? storagePath = media["storage_path"] as String?;
        return <String, dynamic>{
          ...media,
          "signed_url": await _signListingMediaPath(storagePath),
        };
      }),
    );
    return <String, dynamic>{
      "id": row["listing_id"],
      "title": row["title"],
      "description": row["description"],
      "public_location_label": row["public_location_label"],
      "price_amount": row["price_amount"],
      "price_period": row["price_period"],
      "listing_rules": row["listing_rules"],
      "listing_attributes": row["listing_attributes"] ?? <String, dynamic>{},
      "asset_categories": <String, dynamic>{
        "name": row["category_name"],
        "slug": row["category_slug"],
        "field_schema": row["category_field_schema"] ?? <dynamic>[],
      },
      "agent_summary": <String, dynamic>{
        "id": row["agent_id"],
        "display_name": row["agent_display_name"],
        "business_name": row["agent_business_name"],
        "phone_number": row["agent_phone_number"],
        "location_label": row["agent_location_label"],
        "verification_status": row["agent_verification_status"],
        "verified_at": row["agent_verified_at"],
        "profile_photo_url": _publicAgentPhotoUrl(
          row["agent_profile_photo_path"] as String?,
        ),
      },
      "listing_media": signedMedia,
    };
  }

  Future<String?> _signListingMediaPath(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }
    final _SignedUrlCacheEntry? cached = _listingMediaUrlCache[storagePath];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    final String signedUrl = await _client.storage
        .from("listing-media")
        .createSignedUrl(storagePath, _listingMediaSignedUrlSeconds);
    _listingMediaUrlCache[storagePath] = _SignedUrlCacheEntry(
      url: signedUrl,
      expiresAt: DateTime.now().add(
        const Duration(seconds: _listingMediaSignedUrlSeconds - 60),
      ),
    );
    return signedUrl;
  }

  Future<String?> _signPromotionMediaPath(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }
    final _SignedUrlCacheEntry? cached = _promotionMediaUrlCache[storagePath];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }
    final String signedUrl = await _client.storage
        .from("platform-promotions")
        .createSignedUrl(storagePath, _promotionMediaSignedUrlSeconds);
    _promotionMediaUrlCache[storagePath] = _SignedUrlCacheEntry(
      url: signedUrl,
      expiresAt: DateTime.now().add(
        const Duration(seconds: _promotionMediaSignedUrlSeconds - 60),
      ),
    );
    return signedUrl;
  }

  String? _publicAgentPhotoUrl(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }
    return _client.storage.from(_agentPhotoBucket).getPublicUrl(storagePath);
  }

  Future<String> submitGuestRequest({
    required String listingId,
    required String customerName,
    required String customerPhoneNumber,
  }) async {
    final FunctionResponse response = await _client.functions.invoke(
      "create-guest-booking-request",
      body: <String, dynamic>{
        "listing_id": listingId,
        "customer_name": customerName,
        "customer_phone_number": customerPhoneNumber,
      },
    );

    if (response.status >= 400) {
      throw StateError(
        (response.data as Map?)?["error"]?.toString() ?? "Request failed",
      );
    }

    final Map<String, dynamic> payload = response.data as Map<String, dynamic>;
    return payload["requestReference"] as String? ?? "-";
  }
}

class _SignedUrlCacheEntry {
  const _SignedUrlCacheEntry({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}

class _ListCacheEntry<T> {
  const _ListCacheEntry({required this.items, required this.expiresAt});

  final List<T> items;
  final DateTime expiresAt;
}
