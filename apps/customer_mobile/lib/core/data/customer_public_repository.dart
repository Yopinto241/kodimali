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
  // Long-lived URLs work with the disk cache instead of forcing repeated
  // signing and downloads while a customer browses between screens.
  static const int _listingMediaSignedUrlSeconds = 24 * 60 * 60;
  static const int _promotionMediaSignedUrlSeconds = 24 * 60 * 60;
  static const Duration _categoryCacheTtl = Duration(minutes: 30);
  static const Duration _promotionCacheTtl = Duration(minutes: 1);
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

  Future<JsonMap> fetchEventsMarketplace({String? locationId}) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      _client
          .from('event_types')
          .select('id,slug,name_sw,name_en,description_sw,description_en')
          .eq('is_approved', true)
          .order('display_order'),
      _client.rpc(
        'search_public_event_equipment',
        params: <String, dynamic>{
          'p_search': null,
          'p_category_id': null,
          'p_location_id': locationId,
          'p_start_at': null,
          'p_end_at': null,
          'p_min_price': null,
          'p_max_price': null,
          'p_sort': 'recommended',
          'p_limit': 30,
          'p_offset': 0,
        },
      ),
      _client.rpc(
        'search_public_event_services',
        params: <String, dynamic>{
          'p_search': null,
          'p_provider_kind': null,
          'p_location_id': locationId,
          'p_start_at': null,
          'p_end_at': null,
          'p_min_price': null,
          'p_max_price': null,
          'p_sort': 'recommended',
          'p_limit': 30,
          'p_offset': 0,
        },
      ),
    ]);
    return <String, dynamic>{
      'types': (results[0] as List).cast<JsonMap>(),
      'equipment': (results[1] as List).cast<JsonMap>(),
      'services': (results[2] as List).cast<JsonMap>(),
    };
  }

  Future<JsonMap> fetchIndividualEventDetail({
    required String kind,
    required String id,
  }) async {
    if (kind == 'equipment') {
      return (await _client
              .from('event_equipment_items')
              .select(
                'id,name,description,specifications,public_location_label,total_quantity,price_amount_tzs,price_unit,setup_minutes,return_buffer_minutes,transport_configuration,return_procedure,security_deposit_tzs,damage_rules,cancellation_policy,media_paths,event_equipment_categories(name_sw,name_en)',
              )
              .eq('id', id)
              .single())
          .cast<String, dynamic>();
    }
    return (await _client
            .from('event_service_offerings')
            .select(
              'id,title,description,pricing_mode,price_amount_tzs,duration_minutes,requirements,travel_configuration,included_equipment,cancellation_policy,event_service_profiles(id,display_name,provider_kind,biography,experience_years,service_requirements,portfolio_media)',
            )
            .eq('id', id)
            .single())
        .cast<String, dynamic>();
  }

  Future<JsonMap> createIndividualEventBooking({
    required String kind,
    required String id,
    required DateTime startsAt,
    required DateTime endsAt,
    int? quantity,
    String? message,
  }) async =>
      (await _client.rpc(
                'create_individual_event_booking',
                params: <String, dynamic>{
                  'p_kind': kind,
                  'p_equipment_id': kind == 'equipment' ? id : null,
                  'p_offering_id': kind == 'service' ? id : null,
                  'p_start_at': startsAt.toUtc().toIso8601String(),
                  'p_end_at': endsAt.toUtc().toIso8601String(),
                  'p_quantity': kind == 'equipment' ? quantity : null,
                  'p_message': message?.trim(),
                },
              )
              as Map)
          .cast<String, dynamic>();

  Future<List<JsonMap>> fetchMyIndividualEventBookings() async =>
      (await _client
              .from('event_individual_bookings')
              .select(
                'id,reference,booking_kind,requested_period,requested_quantity,quoted_amount_tzs,status,payment_status,provider_response,created_at,event_plan_items(event_equipment_items(name),event_service_offerings(title,event_service_profiles(display_name)))',
              )
              .order('created_at', ascending: false))
          .cast<JsonMap>();

  Future<JsonMap> createEventPlan({
    required String eventTypeId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? locationId,
    String? locationDetails,
    required int attendance,
    double? budgetTzs,
    String? title,
  }) async {
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in to plan an event.');
    }
    final dynamic response = await _client.rpc(
      'create_event_plan',
      params: <String, dynamic>{
        'p_event_type_id': eventTypeId,
        'p_start_at': startsAt.toUtc().toIso8601String(),
        'p_end_at': endsAt.toUtc().toIso8601String(),
        'p_location_id': locationId,
        'p_private_location_details': locationDetails?.trim(),
        'p_attendance': attendance,
        'p_budget_tzs': budgetTzs,
        'p_title': title?.trim(),
      },
    );
    return (response as Map).cast<String, dynamic>();
  }

  Future<List<JsonMap>> fetchEventTemplates() async =>
      (await _client
              .from('event_templates')
              .select(
                'id,slug,name_sw,name_en,description_sw,description_en,setting,event_type_id',
              )
              .eq('is_approved', true)
              .order('name_en'))
          .cast<JsonMap>();

  Future<List<JsonMap>> runEventAdvisor({
    required String planId,
    required String templateId,
    required String setting,
    required String venueStatus,
    String? accessibility,
    String? weatherContingency,
  }) async =>
      (await _client.rpc(
                'run_event_advisor',
                params: <String, dynamic>{
                  'p_plan_id': planId,
                  'p_template_id': templateId,
                  'p_setting': setting,
                  'p_venue_status': venueStatus,
                  'p_accessibility': accessibility,
                  'p_weather_contingency': weatherContingency,
                },
              )
              as List)
          .cast<JsonMap>();

  Future<List<JsonMap>> fetchMyEventPlans() async {
    final plans =
        (await _client
                .from('event_plans')
                .select(
                  'id,reference,title,event_period,attendance,budget_tzs,status,created_at,event_types(name_sw,name_en),event_quote_revisions!event_quote_revisions_plan_id_fkey(id,revision,total_tzs,status,expires_at),event_agreements(id,version,terms,status,sent_at)',
                )
                .order('created_at'))
            .cast<JsonMap>();
    if (plans.isEmpty) return plans;
    List<JsonMap> intents = <JsonMap>[];
    try {
      intents =
          (await _client
                  .from('payment_intents')
                  .select('resource_id,product,amount_minor,status')
                  .eq('resource_type', 'event_plan')
                  .inFilter(
                    'resource_id',
                    plans.map((plan) => plan['id']).toList(growable: false),
                  ))
              .cast<JsonMap>();
    } on PostgrestException catch (error) {
      if (!_isMissingRpcSignature(error) &&
          error.code != '42P01' &&
          error.code != 'PGRST205') {
        rethrow;
      }
    }
    return plans
        .map((plan) {
          final quotes = (plan['event_quote_revisions'] as List? ?? const [])
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value))
              .toList(growable: false);
          final accepted = quotes.where(
            (quote) => quote['status'] == 'accepted',
          );
          final total = accepted.isEmpty
              ? 0
              : (accepted.first['total_tzs'] as num?)?.round() ?? 0;
          final deposit = ((total * 25) + 50) ~/ 100;
          final balance = total - deposit;
          final paid = intents.where(
            (intent) =>
                intent['resource_id'].toString() == plan['id'].toString() &&
                intent['status'] == 'verified_paid',
          );
          final paidDeposit = paid
              .where((intent) => intent['product'] == 'event_deposit')
              .fold<int>(
                0,
                (sum, intent) =>
                    sum + ((intent['amount_minor'] as num?)?.round() ?? 0),
              );
          final paidBalance = paid
              .where((intent) => intent['product'] == 'event_balance')
              .fold<int>(
                0,
                (sum, intent) =>
                    sum + ((intent['amount_minor'] as num?)?.round() ?? 0),
              );
          return <String, dynamic>{
            ...plan,
            'payment_summary': <String, dynamic>{
              'total': total,
              'deposit_remaining': (deposit - paidDeposit).clamp(0, deposit),
              'balance_remaining': (balance - paidBalance).clamp(0, balance),
            },
          };
        })
        .toList(growable: false);
  }

  Future<void> acceptEventQuote(String quoteRevisionId) async {
    await _client.rpc(
      'accept_event_quote',
      params: <String, dynamic>{'p_quote_revision_id': quoteRevisionId},
    );
  }

  Future<void> addEventPlanItem({
    required String planId,
    required String kind,
    String? equipmentId,
    String? offeringId,
    int? quantity,
  }) async {
    await _client.rpc(
      'add_event_plan_item',
      params: <String, dynamic>{
        'p_plan_id': planId,
        'p_item_kind': kind,
        'p_equipment_id': equipmentId,
        'p_offering_id': offeringId,
        'p_quantity': quantity,
        'p_required': true,
        'p_requirements': null,
      },
    );
  }

  Future<void> requestEventQuote(String planId) async {
    await _client.rpc(
      'request_event_quote',
      params: <String, dynamic>{'p_plan_id': planId},
    );
  }

  Future<void> acceptEventAgreement(String agreementId) async {
    await _client.rpc(
      'accept_event_agreement',
      params: <String, dynamic>{'p_agreement_id': agreementId},
    );
  }

  Future<JsonMap> createPlatformPayment({
    required String purpose,
    required String resourceId,
    required String phoneNumber,
  }) async {
    final response = await _client.functions.invoke(
      'create-platform-payment',
      body: <String, dynamic>{
        'purpose': purpose,
        'resource_id': resourceId,
        'phone_number': phoneNumber.trim(),
      },
    );
    if (response.status >= 400 || response.data is! Map) {
      throw StateError(
        (response.data as Map?)?['error']?.toString() ??
            'Could not start payment.',
      );
    }
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['error'] != null) throw StateError(result['error'].toString());
    return result;
  }

  Future<JsonMap> checkPlatformPayment(String paymentId) async {
    final response = await _client.functions.invoke(
      'check-platform-payment',
      body: <String, dynamic>{'payment_id': paymentId},
    );
    if (response.status >= 400 || response.data is! Map) {
      throw StateError(
        (response.data as Map?)?['error']?.toString() ??
            'Could not check payment.',
      );
    }
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['error'] != null) throw StateError(result['error'].toString());
    return result;
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
      List<JsonMap> rows = await _fetchHomeFeedRows(
        limit: page == 0 ? (limit * 5).clamp(50, 100) : limit,
        page: page,
        regionId: regionId,
        districtId: districtId,
        wardId: wardId,
        areaId: areaId,
        latitude: latitude,
        longitude: longitude,
        sessionSeed: sessionSeed,
      );
      if (page == 0 &&
          regionId == null &&
          districtId == null &&
          wardId == null &&
          areaId == null &&
          (latitude == null || longitude == null)) {
        try {
          final List<JsonMap> ranked =
              (await _client.rpc(
                        'get_recommended_listing_ids',
                        params: <String, dynamic>{'p_limit': 100},
                      )
                      as List)
                  .cast<JsonMap>();
          final Map<String, int> order = <String, int>{
            for (int i = 0; i < ranked.length; i++)
              ranked[i]['listing_id'].toString(): i,
          };
          rows = List<JsonMap>.from(rows)
            ..sort(
              (a, b) => (order[a['listing_id']?.toString()] ?? 10000).compareTo(
                order[b['listing_id']?.toString()] ?? 10000,
              ),
            );
          rows = rows.take(limit).toList(growable: false);
        } catch (_) {
          // The regular feed remains available if ranking is temporarily unavailable.
        }
      }
      final Map<String, JsonMap> capabilities = await _fetchBookingCapabilities(
        rows.map((JsonMap row) => row['listing_id']?.toString() ?? ''),
      );
      final List<JsonMap> feed = await Future.wait(
        rows.map(
          (JsonMap row) async => <String, dynamic>{
            ...row,
            "booking_mode":
                capabilities[row['listing_id']
                    ?.toString()]?['effective_mode'] ??
                'request_booking',
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
    double? minPrice,
    double? maxPrice,
    String? pricePeriod,
    String sort = "recommended",
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
      minPrice ?? "",
      maxPrice ?? "",
      pricePeriod ?? "",
      sort,
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
        minPrice: minPrice,
        maxPrice: maxPrice,
        pricePeriod: pricePeriod,
        sort: sort,
      );
      final Map<String, JsonMap> capabilities = await _fetchBookingCapabilities(
        rows.map((JsonMap row) => row['listing_id']?.toString() ?? ''),
      );
      final List<JsonMap> listings = await Future.wait(
        rows.map(
          (JsonMap row) async => <String, dynamic>{
            ...row,
            "booking_mode":
                capabilities[row['listing_id']
                    ?.toString()]?['effective_mode'] ??
                'request_booking',
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

  Future<JsonMap> resolveLocationHierarchy({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final List<JsonMap> rows = (await _client.rpc(
        "resolve_location_hierarchy",
        params: <String, dynamic>{
          "p_latitude": latitude,
          "p_longitude": longitude,
        },
      )).cast<JsonMap>();
      if (rows.isEmpty || rows.first["region_id"] == null) {
        throw StateError("No supported location was found near this device.");
      }
      return rows.first;
    } catch (error) {
      throw _friendlyError(
        error,
        fallbackMessage: "We could not match your GPS position to an area.",
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
    required double? minPrice,
    required double? maxPrice,
    required String? pricePeriod,
    required String sort,
  }) async {
    try {
      return (await _client.rpc(
        "search_public_listings_v2",
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
          "p_min_price": minPrice,
          "p_max_price": maxPrice,
          "p_price_period": pricePeriod,
          "p_sort": sort,
        },
      )).cast<JsonMap>();
    } on PostgrestException catch (error) {
      if (!_isMissingRpcSignature(error)) {
        rethrow;
      }
      // Compatibility while the advanced-search migration is being deployed.
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

  Future<Map<String, JsonMap>> _fetchBookingCapabilities(
    Iterable<String> listingIds,
  ) async {
    final List<String> ids = listingIds
        .where((String id) => id.isNotEmpty)
        .toSet()
        .take(100)
        .toList(growable: false);
    if (ids.isEmpty) return <String, JsonMap>{};
    try {
      final List<JsonMap> rows = (await _client.rpc(
        'get_public_listing_booking_capabilities',
        params: <String, dynamic>{'p_listing_ids': ids},
      )).cast<JsonMap>();
      return <String, JsonMap>{
        for (final JsonMap row in rows)
          if (row['listing_id'] != null && row['capability'] is Map)
            row['listing_id'].toString(): Map<String, dynamic>.from(
              row['capability'] as Map,
            ),
      };
    } on PostgrestException catch (error) {
      if (!_isMissingRpcSignature(error)) rethrow;
      return <String, JsonMap>{};
    }
  }

  Future<JsonMap> fetchBookingQuote({
    required String listingId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final dynamic value = await _client.rpc(
      'get_public_listing_booking_quote',
      params: <String, dynamic>{
        'p_listing_id': listingId,
        'p_start_at': startsAt.toUtc().toIso8601String(),
        'p_end_at': endsAt.toUtc().toIso8601String(),
      },
    );
    if (value is! Map) throw StateError('Booking quote is unavailable.');
    return Map<String, dynamic>.from(value);
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
      JsonMap capability = <String, dynamic>{
        'effective_mode': 'request_booking',
      };
      try {
        final dynamic value = await _client.rpc(
          'get_public_listing_booking_capability',
          params: <String, dynamic>{'p_listing_id': listingId},
        );
        if (value is Map) capability = Map<String, dynamic>.from(value);
      } on PostgrestException catch (error) {
        if (!_isMissingRpcSignature(error)) rethrow;
      }
      JsonMap trust = <String, dynamic>{};
      try {
        final dynamic value = await _client.rpc(
          'agent_trust_summary',
          params: <String, dynamic>{'p_agent_id': row['agent_id']},
        );
        if (value is Map) trust = Map<String, dynamic>.from(value);
      } catch (_) {
        // Listing detail remains available while trust metrics are refreshed.
      }
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
          ...trust,
          "profile_photo_url": _publicAgentPhotoUrl(
            row["agent_profile_photo_path"] as String?,
          ),
        },
        "listing_media": signedMedia,
        "booking_mode": capability['effective_mode'] ?? 'request_booking',
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
        "access_expires_at":
            payload["accessExpiresAt"] ?? cached["access_expires_at"],
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

  Future<JsonMap> submitGuestRequest({
    required String listingId,
    required String customerName,
    String? customerEmail,
    String? customerPhoneNumber,
    DateTime? requestedStartAt,
    DateTime? requestedEndAt,
    int? guestCount,
    String? requestMessage,
    List<String> requestedServiceCodes = const <String>[],
    JsonMap? acceptedQuote,
    bool termsAccepted = false,
  }) async {
    try {
      final String normalizedPhone = customerPhoneNumber?.trim() ?? "";
      final String normalizedEmail = customerEmail?.trim() ?? "";
      final String normalizedMessage = requestMessage?.trim() ?? "";
      if (_client.auth.currentUser != null) {
        final FunctionResponse response = await _client.functions.invoke(
          'create-booking-request',
          body: <String, dynamic>{
            'listingId': listingId,
            'customerName': customerName,
            if (normalizedPhone.isNotEmpty)
              'customerPhoneNumber': normalizedPhone,
            if (normalizedEmail.isNotEmpty) 'customerEmail': normalizedEmail,
            if (requestedStartAt != null)
              'requestedStartAt': requestedStartAt.toUtc().toIso8601String(),
            if (requestedEndAt != null)
              'requestedEndAt': requestedEndAt.toUtc().toIso8601String(),
            'guestCount': ?guestCount,
            if (normalizedMessage.isNotEmpty)
              'requestMessage': normalizedMessage,
            'requestedServiceCodes': requestedServiceCodes,
            'expectedTotalTzs': ?acceptedQuote?['total_tzs'],
            'quoteFingerprint': ?acceptedQuote?['quote_fingerprint'],
            'termsAccepted': termsAccepted,
          },
        );
        if (response.status >= 400 || response.data is! Map) {
          throw StateError(
            _responseErrorMessage(
              response.data,
              fallbackMessage: 'Request failed.',
            ),
          );
        }
        return Map<String, dynamic>.from(response.data as Map);
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
      return payload;
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
