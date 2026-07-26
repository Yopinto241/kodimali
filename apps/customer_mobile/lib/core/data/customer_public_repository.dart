import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../cache/customer_snapshot_store.dart';
import '../media/customer_media_cache.dart';

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
  static const Duration _listingDetailCacheTtl = Duration(seconds: 30);
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
  static final Map<String, _MapCacheEntry<JsonMap>> _listingDetailCache =
      <String, _MapCacheEntry<JsonMap>>{};

  void invalidatePublicDataCache({bool includeCategories = false}) {
    _homeFeedCache.clear();
    _publicListingsCache.clear();
    _promotionsCache.clear();
    _listingDetailCache.clear();
    if (includeCategories) {
      _categoriesCache = null;
    }
  }

  JsonMap? savedListingDetail(String listingId) {
    final _MapCacheEntry<JsonMap>? cached = _listingDetailCache[listingId];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.item;
    }
    return CustomerSnapshotStore.listingDetailForId(listingId);
  }

  Future<void> prefetchListingDetail(String listingId) async {
    try {
      await fetchListingDetail(listingId);
    } catch (_) {
      // Best-effort warmup only.
    }
  }

  Future<bool> fetchContactPaymentsEnabled() async {
    final dynamic enabled = await _client.rpc("contact_payments_enabled");
    return enabled != false;
  }

  Future<List<JsonMap>> fetchCategories() async {
    final _ListCacheEntry<JsonMap>? cached = _categoriesCache;
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return _withApartmentFallback(cached.items);
    }
    try {
      final List<JsonMap> categories =
          (await _client
                  .from("asset_categories")
                  .select(
                    "id, name, slug, description, icon_key, display_order, home_feed_weight",
                  )
                  .eq("is_active", true)
                  .order("display_order")
                  .order("name"))
              .cast<JsonMap>();
      final List<JsonMap> normalizedCategories = _withApartmentFallback(
        categories,
      );
      _categoriesCache = _ListCacheEntry<JsonMap>(
        items: normalizedCategories,
        expiresAt: DateTime.now().add(_categoryCacheTtl),
      );
      unawaited(CustomerSnapshotStore.saveCategories(normalizedCategories));
      return normalizedCategories;
    } catch (error) {
      final List<JsonMap> fallback = _withApartmentFallback(
        CustomerSnapshotStore.categories,
      );
      if (fallback.isNotEmpty) {
        return fallback;
      }
      throw _friendlyError(
        error,
        fallbackMessage: "We could not load categories right now.",
      );
    }
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
    final String snapshotKey = CustomerSnapshotStore.buildScopedKey(
      scope: "home",
      regionId: regionId,
      districtId: districtId,
      wardId: wardId,
      areaId: areaId,
      latitude: latitude,
      longitude: longitude,
    );
    try {
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
            "cover_media_type": _isVideoPath(row["cover_storage_path"])
                ? "video"
                : "image",
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
        unawaited(CustomerSnapshotStore.saveHomeFeed(snapshotKey, feed));
      }
      _prefetchListingCovers(feed);
      return feed;
    } catch (error) {
      if (page == 0) {
        final List<JsonMap>? snapshot = CustomerSnapshotStore.homeFeedForKey(
          snapshotKey,
        );
        if (snapshot != null && snapshot.isNotEmpty) {
          _prefetchListingCovers(snapshot);
          return snapshot;
        }
      }
      throw _friendlyError(
        error,
        fallbackMessage: "We could not load listings right now.",
      );
    }
  }

  Future<List<JsonMap>> fetchPromotions({
    required String surface,
    String placement = "global",
    int limit = 3,
    String? regionId,
    String? districtId,
    String? wardId,
    String? areaId,
  }) async {
    final String cacheKey = [
      surface,
      placement,
      limit,
      regionId ?? "",
      districtId ?? "",
      wardId ?? "",
      areaId ?? "",
    ].join("|");
    final _ListCacheEntry<JsonMap>? cached = _promotionsCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.items;
    }
    try {
      final List<JsonMap> rows = await _fetchPromotionRows(
        surface: surface,
        placement: placement,
        limit: limit,
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: areaId,
      );
      final List<JsonMap> promotions = await Future.wait(
        rows.map(
          (JsonMap row) async => <String, dynamic>{
            ...row,
            "cover_media_type": _isVideoPath(row["cover_storage_path"])
                ? "video"
                : "image",
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
    } catch (_) {
      return cached?.items ?? <JsonMap>[];
    }
  }

  Future<List<JsonMap>> _fetchPromotionRows({
    required String surface,
    required String placement,
    required int limit,
    required String? regionId,
    required String? districtId,
    required String? wardId,
    required String? areaId,
  }) async {
    try {
      return (await _client.rpc(
        "get_active_platform_promotions",
        params: <String, dynamic>{
          "p_surface": surface,
          "p_placement": placement,
          "p_limit": limit,
          "p_selected_region_id": regionId,
          "p_selected_district_id": districtId,
          "p_selected_ward_id": wardId,
          "p_selected_area_id": areaId,
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
          "p_selected_region_id": regionId,
          "p_selected_district_id": districtId,
          "p_selected_ward_id": wardId,
          "p_selected_area_id": areaId,
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
    final String? snapshotKey = page == 0 && (categorySlug?.isNotEmpty == true)
        ? CustomerSnapshotStore.buildScopedKey(
            scope: categorySlug!,
            regionId: regionId,
            districtId: districtId,
            wardId: wardId,
            areaId: areaId,
            latitude: latitude,
            longitude: longitude,
          )
        : null;
    try {
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
      if (snapshotKey != null) {
        unawaited(
          CustomerSnapshotStore.savePublicListings(snapshotKey, listings),
        );
      }
      _prefetchListingCovers(listings);
      return listings;
    } catch (error) {
      if (snapshotKey != null) {
        final List<JsonMap>? snapshot =
            CustomerSnapshotStore.publicListingsForKey(snapshotKey);
        if (snapshot != null && snapshot.isNotEmpty) {
          _prefetchListingCovers(snapshot);
          return snapshot;
        }
      }
      throw _friendlyError(
        error,
        fallbackMessage: "We could not load listings right now.",
      );
    }
  }

  Future<List<JsonMap>> fetchLocations({
    required String? parentId,
    required String locationType,
  }) async {
    try {
      dynamic query = _client
          .from("locations")
          .select("id, name, location_type, parent_id")
          .eq("location_type", locationType)
          .eq("is_active", true);
      query = parentId == null
          ? query.filter("parent_id", "is", "null")
          : query.eq("parent_id", parentId);
      return (await query.order("name")).cast<JsonMap>();
    } catch (error) {
      throw _friendlyError(
        error,
        fallbackMessage: "We could not load locations right now.",
      );
    }
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

  Future<JsonMap> fetchListingDetail(
    String listingId, {
    bool forceRefresh = false,
  }) async {
    final _MapCacheEntry<JsonMap>? cached = _listingDetailCache[listingId];
    if (!forceRefresh &&
        cached != null &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return cached.item;
    }
    final JsonMap? snapshot = CustomerSnapshotStore.listingDetailForId(
      listingId,
    );
    try {
      final List<dynamic> rows = await _client.rpc(
        "get_public_listing_detail",
        params: <String, dynamic>{"p_listing_id": listingId},
      );
      if (rows.isEmpty) {
        await _clearListingDetailCache(listingId);
        throw StateError("Listing not found.");
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
      final JsonMap detail = <String, dynamic>{
        "id": row["listing_id"],
        "listing_location_id": row["listing_location_id"],
        "region_id": row["region_id"],
        "district_id": row["district_id"],
        "ward_id": row["ward_id"],
        "area_id": row["area_id"],
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
      _listingDetailCache[listingId] = _MapCacheEntry<JsonMap>(
        item: detail,
        expiresAt: DateTime.now().add(_listingDetailCacheTtl),
      );
      unawaited(CustomerSnapshotStore.saveListingDetail(listingId, detail));
      _prefetchListingDetailMedia(signedMedia);
      return detail;
    } catch (error) {
      if (_isListingUnavailableError(error)) {
        await _clearListingDetailCache(listingId);
      } else if (snapshot != null && snapshot.isNotEmpty) {
        return snapshot;
      }
      throw _friendlyError(
        error,
        fallbackMessage: "We could not load this listing right now.",
      );
    }
  }

  JsonMap? savedContactAccess(String listingId) {
    return CustomerSnapshotStore.contactAccessForListing(listingId);
  }

  Future<void> clearSavedContactAccess(String listingId) {
    return CustomerSnapshotStore.clearContactAccess(listingId);
  }

  Future<JsonMap> createListingContactPayment({
    required String listingId,
    required String customerName,
    required String customerPhoneNumber,
    String? customerEmail,
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        "create-listing-contact-payment",
        body: <String, dynamic>{
          "listing_id": listingId,
          "customer_name": customerName,
          "customer_phone_number": customerPhoneNumber,
          if (customerEmail != null && customerEmail.trim().isNotEmpty)
            "customer_email": customerEmail.trim(),
        },
      );

      if (response.status >= 400) {
        throw StateError(
          _responseErrorMessage(
            response.data,
            fallbackMessage: "Could not start the payment.",
          ),
        );
      }

      final JsonMap payload = (response.data as Map).cast<String, dynamic>();
      final JsonMap cached = <String, dynamic>{
        "payment_id": payload["paymentId"],
        "access_token": payload["accessToken"],
        "order_reference": payload["orderReference"],
        "amount": payload["amount"],
        "currency": payload["currency"],
        "status": payload["paymentStatus"] ?? "pending",
        "payment_method": payload["paymentMethod"],
        "sender_name": payload["senderName"],
        "message": payload["message"],
        "customer_phone_number": customerPhoneNumber.trim(),
        "phone_number": null,
        "updated_at": DateTime.now().toIso8601String(),
      };
      await CustomerSnapshotStore.saveContactAccess(listingId, cached);
      return cached;
    } catch (error) {
      throw _friendlyError(
        error,
        fallbackMessage: "We could not start the payment right now.",
      );
    }
  }

  Future<JsonMap> checkListingContactPayment(String listingId) async {
    final JsonMap? cached = CustomerSnapshotStore.contactAccessForListing(
      listingId,
    );
    if (cached == null) {
      throw StateError("No saved payment was found for this listing.");
    }

    try {
      final FunctionResponse response = await _client.functions.invoke(
        "check-listing-contact-payment",
        body: <String, dynamic>{
          "payment_id": cached["payment_id"],
          "access_token": cached["access_token"],
        },
      );

      if (response.status >= 400) {
        throw StateError(
          _responseErrorMessage(
            response.data,
            fallbackMessage: "Could not verify the payment.",
          ),
        );
      }

      final JsonMap payload = (response.data as Map).cast<String, dynamic>();
      final JsonMap updated = <String, dynamic>{
        ...cached,
        "status": payload["paymentStatus"] ?? cached["status"],
        "message": payload["message"],
        "phone_number": payload["phoneNumber"] ?? cached["phone_number"],
        "agent_display_name":
            payload["agentDisplayName"] ?? cached["agent_display_name"],
        "updated_at": DateTime.now().toIso8601String(),
      };
      await CustomerSnapshotStore.saveContactAccess(listingId, updated);
      return updated;
    } catch (error) {
      throw _friendlyError(
        error,
        fallbackMessage: "We could not verify the payment right now.",
      );
    }
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

  Future<JsonMap> checkListingAvailability({
    required String listingId,
    DateTime? requestedStartAt,
    DateTime? requestedEndAt,
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        "check-availability",
        body: <String, dynamic>{
          "listingId": listingId,
          if (requestedStartAt != null)
            "requestedStartAt": requestedStartAt.toUtc().toIso8601String(),
          if (requestedEndAt != null)
            "requestedEndAt": requestedEndAt.toUtc().toIso8601String(),
        },
      );

      if (response.status >= 400) {
        throw StateError(
          _responseErrorMessage(
            response.data,
            fallbackMessage: "Availability check failed.",
          ),
        );
      }

      return (response.data as Map).cast<String, dynamic>();
    } catch (error) {
      throw _friendlyError(
        error,
        fallbackMessage: "We could not check availability right now.",
      );
    }
  }

  Future<void> _clearListingDetailCache(String listingId) async {
    _listingDetailCache.remove(listingId);
    await CustomerSnapshotStore.clearListingDetail(listingId);
  }

  bool _isListingUnavailableError(Object error) {
    final String message = error.toString().toLowerCase();
    return message.contains("listing not found") ||
        message.contains("listing is not available") ||
        message.contains("not available");
  }

  Future<String> submitGuestRequest({
    required String listingId,
    required String customerName,
    String? customerEmail,
    String? customerPhoneNumber,
    DateTime? requestedStartAt,
    DateTime? requestedEndAt,
    int? guestCount,
    String? requestMessage,
    List<String> requestedServiceCodes = const <String>[],
  }) async {
    try {
      final String normalizedPhone = customerPhoneNumber?.trim() ?? "";
      final String normalizedEmail = customerEmail?.trim() ?? "";
      final String normalizedMessage = requestMessage?.trim() ?? "";
      if (_client.auth.currentUser != null) {
        final dynamic authenticatedResponse = await _client.rpc(
          'create_authenticated_booking_request',
          params: <String, dynamic>{
            'p_listing_id': listingId,
            'p_customer_name': customerName,
            'p_customer_phone_number': normalizedPhone.isEmpty
                ? null
                : normalizedPhone,
            'p_customer_email': normalizedEmail.isEmpty
                ? null
                : normalizedEmail,
            'p_requested_start_at': requestedStartAt?.toUtc().toIso8601String(),
            'p_requested_end_at': requestedEndAt?.toUtc().toIso8601String(),
            'p_guest_count': guestCount,
            'p_request_message': normalizedMessage.isEmpty
                ? null
                : normalizedMessage,
            'p_requested_service_codes': requestedServiceCodes,
          },
        );
        final JsonMap? authenticatedBooking = switch (authenticatedResponse) {
          final Map<dynamic, dynamic> row => row.cast<String, dynamic>(),
          final List<dynamic> rows when rows.isNotEmpty && rows.first is Map =>
            (rows.first as Map).cast<String, dynamic>(),
          _ => null,
        };
        if (authenticatedBooking == null) {
          throw StateError('Request failed.');
        }
        return authenticatedBooking['request_reference']?.toString() ?? '-';
      }
      final FunctionResponse response = await _client.functions.invoke(
        "create-guest-booking-request",
        body: <String, dynamic>{
          "listing_id": listingId,
          "customer_name": customerName,
          if (normalizedEmail.isNotEmpty) "customer_email": normalizedEmail,
          if (normalizedPhone.isNotEmpty)
            "customer_phone_number": normalizedPhone,
          if (requestedStartAt != null)
            "requested_start_at": requestedStartAt.toUtc().toIso8601String(),
          if (requestedEndAt != null)
            "requested_end_at": requestedEndAt.toUtc().toIso8601String(),
          if (guestCount case final int guests) "guest_count": guests,
          if (normalizedMessage.isNotEmpty)
            "request_message": normalizedMessage,
          if (requestedServiceCodes.isNotEmpty)
            "requested_service_codes": requestedServiceCodes,
        },
      );

      if (response.status >= 400) {
        throw StateError(
          _responseErrorMessage(
            response.data,
            fallbackMessage: "Request failed.",
          ),
        );
      }

      final Map<String, dynamic> payload =
          response.data as Map<String, dynamic>;
      return payload["requestReference"] as String? ?? "-";
    } catch (error) {
      if (_isListingUnavailableError(error)) {
        await _clearListingDetailCache(listingId);
        invalidatePublicDataCache();
        throw StateError(
          "This listing is no longer available. Refresh the listings and choose another one.",
        );
      }
      throw _friendlyError(
        error,
        fallbackMessage: "We could not send your request right now.",
      );
    }
  }

  void _prefetchListingCovers(List<JsonMap> listings) {
    for (final JsonMap listing in listings.take(8)) {
      final String? url = listing["cover_url"] as String?;
      if (url == null || url.isEmpty) {
        continue;
      }
      if (listing["cover_media_type"] == "video") {
        continue;
      }
      final String key =
          listing["cover_storage_path"] as String? ??
          listing["listing_id"] as String? ??
          url;
      unawaited(CustomerMediaCacheManager.instance.downloadFile(url, key: key));
    }
  }

  bool _isVideoPath(dynamic value) =>
      value is String &&
      RegExp(r'\.(mp4|webm|mov)$', caseSensitive: false).hasMatch(value);

  void _prefetchListingDetailMedia(List<JsonMap> mediaItems) {
    for (final JsonMap media in mediaItems.take(5)) {
      final String? url = media["signed_url"] as String?;
      if (url == null || url.isEmpty || media["media_type"] == "video") {
        continue;
      }
      final String key = media["storage_path"] as String? ?? url;
      unawaited(CustomerMediaCacheManager.instance.downloadFile(url, key: key));
    }
  }

  StateError _friendlyError(Object error, {required String fallbackMessage}) {
    final String message = _stripErrorPrefix(error.toString());
    final String normalized = message.toLowerCase();
    if (error is StateError && !_looksLikeTechnicalNoise(message)) {
      return StateError(message);
    }
    if (error is SocketException || _looksOffline(normalized)) {
      return StateError(
        "No internet connection. Please check your network and try again.",
      );
    }
    if (error is TimeoutException || normalized.contains("timeout")) {
      return StateError(
        "The request took too long. Please try again in a moment.",
      );
    }
    if (error is PostgrestException && !_looksLikeTechnicalNoise(message)) {
      return StateError(message);
    }
    if (!_looksLikeTechnicalNoise(message)) {
      return StateError(message);
    }
    return StateError(fallbackMessage);
  }

  bool _looksOffline(String text) {
    return text.contains("failed host lookup") ||
        text.contains("socketexception") ||
        text.contains("clientexception") ||
        text.contains("connection closed") ||
        text.contains("network is unreachable") ||
        text.contains("connection refused") ||
        text.contains("xmlhttprequest error") ||
        text.contains("connection error");
  }

  bool _looksLikeTechnicalNoise(String text) {
    final String trimmed = text.trim();
    return trimmed.isEmpty ||
        trimmed.contains("postgrestexception") ||
        trimmed.contains("functionresponse") ||
        trimmed.contains("xmlhttprequest") ||
        trimmed.contains("socketexception") ||
        trimmed.contains("clientexception");
  }

  String _responseErrorMessage(
    dynamic data, {
    required String fallbackMessage,
  }) {
    if (data is Map) {
      final Object? error = data["error"] ?? data["message"];
      if (error != null) {
        final String message = _stripErrorPrefix(error.toString());
        if (message.isNotEmpty) {
          return message;
        }
      }
    } else if (data != null) {
      final String message = _stripErrorPrefix(data.toString());
      if (message.isNotEmpty) {
        return message;
      }
    }
    return fallbackMessage;
  }

  String _stripErrorPrefix(String text) {
    return text
        .replaceFirst("Bad state: ", "")
        .replaceFirst("Exception: ", "")
        .trim();
  }

  List<JsonMap> _withApartmentFallback(List<JsonMap> categories) {
    final List<JsonMap> normalized = categories
        .map((JsonMap row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final bool hasApartment = normalized.any(
      (JsonMap row) => row["slug"] == "apartment",
    );
    if (hasApartment) {
      return normalized;
    }
    return <JsonMap>[
      <String, dynamic>{
        "id": "apartment-fallback",
        "name": "Apartment",
        "slug": "apartment",
        "description":
            "Serviced apartments, flats, and short-stay homes for local and international guests.",
        "icon_key": "apartment",
        "display_order": 2,
        "home_feed_weight": 9,
      },
      ...normalized,
    ];
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

class _MapCacheEntry<T> {
  const _MapCacheEntry({required this.item, required this.expiresAt});

  final T item;
  final DateTime expiresAt;
}
