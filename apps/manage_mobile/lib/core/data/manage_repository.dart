import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_profile.dart';
import '../models/upload_task.dart';

typedef JsonMap = Map<String, dynamic>;

class ManageRepository {
  ManageRepository(this._client);

  final SupabaseClient _client;
  static const String _agentPhotoBucket = "agent-profile-photos";
  static const int _agentPhotoMaxBytes = 5 * 1024 * 1024;
  static const int _listingVideoMaxBytes = 30 * 1024 * 1024;
  static const int _promotionMediaMaxBytes = 30 * 1024 * 1024;
  static const int _signedMediaUrlSeconds = 60;
  static const int _pagedQueryBatchSize = 1000;
  static const Duration _registrationLookupCacheTtl = Duration(minutes: 3);

  List<JsonMap>? _agentAssignmentCategoriesCache;
  DateTime? _agentAssignmentCategoriesCachedAt;
  List<JsonMap>? _agentLocationHierarchyCache;
  DateTime? _agentLocationHierarchyCachedAt;

  User? get currentUser => _client.auth.currentUser;

  bool _cacheFresh(DateTime? cachedAt) {
    if (cachedAt == null) {
      return false;
    }
    return DateTime.now().difference(cachedAt) <= _registrationLookupCacheTtl;
  }

  List<JsonMap> _cloneRows(List<JsonMap> rows) {
    return rows
        .map((JsonMap row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  void _invalidateLocationCaches() {
    _agentLocationHierarchyCache = null;
    _agentLocationHierarchyCachedAt = null;
  }

  Future<List<JsonMap>> _decodeListRows(Future<dynamic> response) async {
    final dynamic data = await response;
    if (data is List) {
      return data
          .map((dynamic row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (data is Map) {
      return <JsonMap>[Map<String, dynamic>.from(data)];
    }
    return <JsonMap>[];
  }

  Future<List<JsonMap>> _decodePagedRows(
    dynamic Function(int from, int to) queryBuilder, {
    int batchSize = _pagedQueryBatchSize,
  }) async {
    final List<JsonMap> rows = <JsonMap>[];
    int from = 0;

    while (true) {
      final int to = from + batchSize - 1;
      final List<JsonMap> batch = await _decodeListRows(queryBuilder(from, to));
      rows.addAll(batch);
      if (batch.length < batchSize) {
        break;
      }
      from += batchSize;
    }

    return rows;
  }

  bool _containsCategorySlug(List<JsonMap> rows, String slug) {
    for (final JsonMap row in rows) {
      if ((row["slug"] as String?) == slug) {
        return true;
      }
    }
    return false;
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    try {
      final String trimmedIdentifier = identifier.trim();
      if (trimmedIdentifier.contains("@")) {
        await _client.auth.signInWithPassword(
          email: trimmedIdentifier,
          password: password,
        );
        return;
      }

      final JsonMap? resolved;
      try {
        resolved = await _resolveLoginIdentifier(trimmedIdentifier);
      } on PostgrestException catch (error) {
        if (_isManageIdentifierCompatibilityError(error)) {
          throw StateError(
            "Username and phone login need the latest Supabase migration. Use email and password for now.",
          );
        }
        rethrow;
      }
      final String? accountEmail = resolved?["account_email"] as String?;
      final String loginEmail = accountEmail?.trim().isNotEmpty == true
          ? accountEmail!.trim()
          : trimmedIdentifier;

      if (loginEmail.isEmpty || !loginEmail.contains("@")) {
        throw StateError(
          "We could not find an account with that username, phone number, or email.",
        );
      }

      await _client.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );
    } on AuthException catch (error) {
      throw StateError(_friendlyAuthError(error));
    } on PostgrestException catch (error) {
      throw StateError(_friendlyAreaError(error));
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError("We could not sign you in right now. Please try again.");
    }
  }

  Future<void> registerAgentAccount({
    required String fullName,
    required String username,
    required String phoneNumber,
    required String activationEmail,
    required String password,
    required String locationId,
    required String nidaNumber,
    required String primaryCategoryId,
    required String businessName,
    String? businessDescription,
    required String preferredLanguage,
  }) async {
    try {
      final JsonMap? usernameMatch;
      final JsonMap? phoneMatch;
      final JsonMap? emailMatch;
      try {
        usernameMatch = await _resolveLoginIdentifier(username);
        phoneMatch = await _resolveLoginIdentifier(phoneNumber);
        emailMatch = await _resolveLoginIdentifier(activationEmail);
      } on PostgrestException catch (error) {
        if (_isManageIdentifierCompatibilityError(error)) {
          throw StateError(
            "Agent self-registration needs the latest Supabase migration before it can be used.",
          );
        }
        rethrow;
      }

      if (usernameMatch?["matched_by"] == "username") {
        throw StateError("That username is already in use.");
      }

      if (phoneMatch?["matched_by"] == "phone") {
        throw StateError(
          "That phone number is already linked to another account.",
        );
      }

      if (emailMatch?["matched_by"] == "email") {
        throw StateError("That email is already linked to another account.");
      }

      await _client.auth.signUp(
        email: activationEmail,
        password: password,
        data: <String, dynamic>{
          "full_name": fullName,
          "username": username,
          "phone_number": phoneNumber,
          "preferred_language": preferredLanguage,
          "register_as_agent": true,
          "registration_source": "agent_self_register",
          "location_id": locationId,
          "nida_number": nidaNumber,
          "business_name": businessName,
          "business_description": businessDescription,
          "primary_category_id": primaryCategoryId,
        },
      );
      // With Supabase autoconfirm enabled, signUp can create a live session.
      // Registration should still return the user to the normal login flow
      // while admin approval remains the final gate.
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw StateError(_friendlyAuthError(error));
    } on PostgrestException catch (error) {
      throw StateError(_friendlyAreaError(error));
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        "We could not finish registration right now. Please try again.",
      );
    }
  }

  Future<bool> isUsernameAvailable(String username) async {
    final String normalized = username.trim().toLowerCase();
    if (!RegExp(r"^[a-z0-9_]{3,32}$").hasMatch(normalized)) {
      return false;
    }
    try {
      final JsonMap? match = await _resolveLoginIdentifier(normalized);
      return match?["matched_by"] != "username";
    } on PostgrestException catch (error) {
      if (_isManageIdentifierCompatibilityError(error)) {
        throw StateError(
          "Username checks need the latest Supabase migration before they can run.",
        );
      }
      rethrow;
    }
  }

  Future<JsonMap?> lookupLoginIdentifier(String identifier) async {
    try {
      return await _resolveLoginIdentifier(identifier);
    } on PostgrestException catch (error) {
      if (_isManageIdentifierCompatibilityError(error)) {
        throw StateError(
          "Identifier checks need the latest Supabase migration before they can run.",
        );
      }
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String identifier) async {
    try {
      final String trimmedIdentifier = identifier.trim();
      if (trimmedIdentifier.isEmpty) {
        throw StateError("Enter your username, phone number, or email first.");
      }

      final JsonMap? resolved = await lookupLoginIdentifier(trimmedIdentifier);
      final String? resolvedEmail =
          resolved?["account_email"] as String? ??
          (trimmedIdentifier.contains("@") ? trimmedIdentifier : null);
      final String loginEmail = resolvedEmail?.trim() ?? "";

      if (loginEmail.isEmpty || !loginEmail.contains("@")) {
        throw StateError(
          "We could not find an account with that username, phone number, or email.",
        );
      }

      if (_isInternalManageAccountEmail(loginEmail)) {
        throw StateError(
          "This account has no recovery email. Ask an admin to reset it, or sign in and change the password from Profile.",
        );
      }

      await _client.auth.resetPasswordForEmail(loginEmail);
    } on AuthException catch (error) {
      throw StateError(_friendlyAuthError(error));
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        "We could not send the password reset link right now. Please try again.",
      );
    }
  }

  Future<void> updatePassword(String newPassword) async {
    if (newPassword.length < 6) {
      throw StateError("Password must be at least 6 characters.");
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw StateError(_friendlyAuthError(error));
    } catch (_) {
      throw StateError(
        "We could not change the password right now. Please try again.",
      );
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<AppProfile> fetchProfile(String userId) async {
    JsonMap? profile;
    try {
      profile = await _client
          .from("profiles")
          .select(
            "id, full_name, username, account_email, account_email_confirmed_at, phone_number, preferred_language",
          )
          .eq("id", userId)
          .maybeSingle();
    } on PostgrestException catch (error) {
      if (!_isManageIdentifierCompatibilityError(error)) {
        rethrow;
      }
      profile = await _client
          .from("profiles")
          .select("id, full_name, phone_number, preferred_language")
          .eq("id", userId)
          .maybeSingle();
    }
    final List<dynamic> rolesRaw = await _client
        .from("user_roles")
        .select("role")
        .eq("profile_id", userId);
    final User? user = currentUser;
    final String fullName =
        (profile?["full_name"] as String?)?.trim().isNotEmpty == true
        ? (profile?["full_name"] as String).trim()
        : (user?.userMetadata?["full_name"]?.toString().trim().isNotEmpty ==
                  true
              ? user!.userMetadata!["full_name"].toString().trim()
              : (user?.email ?? "KODIMALI User"));
    final String? phoneNumber =
        (profile?["phone_number"] as String?) ??
        user?.userMetadata?["phone_number"]?.toString();
    final String preferredLanguage =
        (profile?["preferred_language"] as String?) ??
        user?.userMetadata?["preferred_language"]?.toString() ??
        "sw";
    final String? accountEmailFromProfile =
        profile?["account_email"] as String?;
    final String? accountEmail =
        accountEmailFromProfile?.trim().isNotEmpty == true
        ? accountEmailFromProfile
        : user?.email;

    final List<AppRole> roles = rolesRaw
        .map((dynamic item) => (item as JsonMap)["role"] as String?)
        .whereType<String>()
        .map(_parseRole)
        .toList();
    final JsonMap? agent = await _myAgentStatus();

    return AppProfile(
      id: (profile?["id"] as String?) ?? userId,
      fullName: fullName,
      username: profile?["username"] as String?,
      accountEmail: accountEmail,
      accountEmailConfirmedAt: DateTime.tryParse(
        profile?["account_email_confirmed_at"]?.toString() ?? "",
      ),
      phoneNumber: phoneNumber,
      preferredLanguage: preferredLanguage,
      roles: roles.isEmpty ? <AppRole>[AppRole.customer] : roles,
      agentDisplayName: agent?["display_name"] as String?,
      agentPhoneNumber: agent?["phone_number"] as String?,
      agentContactEmail: agent?["contact_email"] as String?,
      agentNidaNumber: agent?["nida_number"] as String?,
      agentLocationLabel: agent?["public_location_label"] as String?,
      agentProfilePhotoUrl: _publicAgentPhotoUrl(
        agent?["profile_photo_path"] as String?,
      ),
      agentBusinessName: agent?["business_name"] as String?,
      agentVerifiedAt: DateTime.tryParse(
        agent?["verified_at"]?.toString() ?? "",
      ),
      agentAccountStatus: agent?["account_status"] as String?,
      agentVerificationStatus: agent?["verification_status"] as String?,
    );
  }

  Future<Map<String, int>> fetchAgentDashboardCounts(String userId) async {
    final JsonMap? agent = await _maybeCurrentAgent();
    if (agent == null) {
      return <String, int>{};
    }
    final String agentId = agent["id"] as String;
    final int activeListings = await _count(
      _client
          .from("listings")
          .select("id")
          .eq("agent_id", agentId)
          .eq("status", "active"),
    );
    final int inactiveListings = await _count(
      _client
          .from("listings")
          .select("id")
          .eq("agent_id", agentId)
          .eq("status", "inactive"),
    );
    final int newRequests = await _count(
      _client
          .from("booking_requests")
          .select("id")
          .eq("agent_id", agentId)
          .eq("booking_status", "new"),
    );
    final int totalInquiries = await _count(
      _client.from("booking_requests").select("id").eq("agent_id", agentId),
    );
    final int unreadNotifications = await _count(
      _client
          .from("notifications")
          .select("id")
          .eq("user_id", userId)
          .filter("read_at", "is", "null"),
    );
    return <String, int>{
      "activeListings": activeListings,
      "inactiveListings": inactiveListings,
      "newRequests": newRequests,
      "totalInquiries": totalInquiries,
      "unreadNotifications": unreadNotifications,
    };
  }

  Future<Map<String, int>> fetchAdminDashboardCounts(String userId) async {
    final int inactiveAgents = await _count(
      _client.from("agents").select("id").neq("account_status", "active"),
    );
    final int liveListings = await _count(
      _client.from("listings").select("id").eq("status", "active"),
    );
    final int totalInquiries = await _count(
      _client.from("booking_requests").select("id"),
    );
    final int unreadNotifications = await _count(
      _client
          .from("notifications")
          .select("id")
          .eq("user_id", userId)
          .filter("read_at", "is", "null"),
    );
    return <String, int>{
      "inactiveAgents": inactiveAgents,
      "liveListings": liveListings,
      "reports": 0,
      "totalInquiries": totalInquiries,
      "unreadNotifications": unreadNotifications,
    };
  }

  Future<JsonMap> fetchMarketplaceSettings() async {
    try {
      final JsonMap? row = await _client
          .from("marketplace_settings")
          .select("contact_payments_enabled, updated_at")
          .eq("id", true)
          .maybeSingle();
      return row ?? <String, dynamic>{"contact_payments_enabled": true};
    } on PostgrestException catch (error) {
      if (_isManageIdentifierCompatibilityError(error)) {
        throw StateError(
          "Marketplace settings need the latest Supabase migration before this toggle can be used.",
        );
      }
      rethrow;
    }
  }

  Future<void> updateContactPaymentsEnabled(bool enabled) async {
    final User user = _requireUser();
    try {
      await _client.from("marketplace_settings").upsert(<String, dynamic>{
        "id": true,
        "contact_payments_enabled": enabled,
        "updated_by": user.id,
      });
    } on PostgrestException catch (error) {
      if (_isManageIdentifierCompatibilityError(error)) {
        throw StateError(
          "Marketplace settings need the latest Supabase migration before this toggle can be used.",
        );
      }
      rethrow;
    }
  }

  Future<void> submitAgentApplication({
    required String businessName,
    required String phoneNumber,
    required String? businessDescription,
    required PlatformFile document,
  }) async {
    final User user = _requireUser();
    final List<dynamic> rows = await _client.rpc(
      "submit_agent_application",
      params: <String, dynamic>{
        "p_business_name": businessName,
        "p_business_description": businessDescription,
        "p_phone_number": phoneNumber,
      },
    );
    if (rows.isEmpty) {
      throw StateError("Could not create agent application");
    }
    final JsonMap agent = (rows.first as Map).cast<String, dynamic>();
    final String agentId = agent["agent_id"] as String;

    final String path = "${user.id}/${_safeFileName(document.name)}";
    await _client.storage
        .from("agent-documents")
        .uploadBinary(
          path,
          document.bytes!,
          fileOptions: const FileOptions(upsert: true),
        );

    await _client.from("agent_documents").insert(<String, dynamic>{
      "agent_id": agentId,
      "document_type": _documentTypeFromName(document.name),
      "storage_path": path,
      "review_notes": businessDescription,
    });
  }

  Future<List<JsonMap>> fetchOwnersForCurrentAgent() async {
    final JsonMap agent = await _currentAgent();
    return _decodeListRows(
      _client
          .from("owners")
          .select("id, full_name, phone_number, notes, location_id, created_at")
          .eq("agent_id", agent["id"] as String)
          .order("created_at", ascending: false),
    );
  }

  Future<List<JsonMap>> fetchActiveCategories() async {
    if (currentUser == null) {
      return _decodeListRows(
        _client
            .from("asset_categories")
            .select(
              "id, name, slug, description, icon_key, display_order, is_active, home_feed_weight, field_schema",
            )
            .eq("is_active", true)
            .order("display_order")
            .order("name"),
      );
    }

    final JsonMap? agent = await _maybeCurrentAgent();
    if (agent == null) {
      return _decodeListRows(
        _client
            .from("asset_categories")
            .select(
              "id, name, slug, description, icon_key, display_order, is_active, home_feed_weight, field_schema",
            )
            .eq("is_active", true)
            .order("display_order")
            .order("name"),
      );
    }

    final List<JsonMap> rows = await _decodeListRows(
      _client
          .from("agent_service_categories")
          .select(
            "category_id, is_primary, asset_categories!inner(id, name, slug, description, icon_key, display_order, is_active, home_feed_weight, field_schema)",
          )
          .eq("agent_id", agent["id"] as String)
          .order("is_primary", ascending: false),
    );

    final List<JsonMap> categories = <JsonMap>[];
    for (final JsonMap row in rows) {
      final JsonMap? category = (row["asset_categories"] as Map?)
          ?.cast<String, dynamic>();
      if (category == null || category["is_active"] != true) {
        continue;
      }
      categories.add(<String, dynamic>{
        ...category,
        "is_primary_assignment": row["is_primary"] == true,
      });
    }
    categories.sort((JsonMap a, JsonMap b) {
      final int primaryCompare = ((b["is_primary_assignment"] == true) ? 1 : 0)
          .compareTo((a["is_primary_assignment"] == true) ? 1 : 0);
      if (primaryCompare != 0) {
        return primaryCompare;
      }
      final int displayCompare = ((a["display_order"] as num?)?.toInt() ?? 0)
          .compareTo((b["display_order"] as num?)?.toInt() ?? 0);
      if (displayCompare != 0) {
        return displayCompare;
      }
      return (a["name"] as String? ?? "").compareTo(b["name"] as String? ?? "");
    });
    return categories;
  }

  Future<List<JsonMap>> fetchCategoriesForAdmin() async {
    return _decodeListRows(
      _client
          .from("asset_categories")
          .select(
            "id, name, slug, description, icon_key, display_order, is_active, home_feed_weight, field_schema",
          )
          .order("display_order")
          .order("name"),
    );
  }

  Future<List<JsonMap>> fetchPromotionsForSurface({
    required String surface,
    String placement = "global",
    int limit = 3,
  }) async {
    final List<JsonMap> rows = await _fetchPromotionRows(
      surface: surface,
      placement: placement,
      limit: limit,
    );
    return Future.wait(
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
  }

  Future<List<JsonMap>> _fetchPromotionRows({
    required String surface,
    required String placement,
    required int limit,
  }) async {
    try {
      return _decodeListRows(
        _client.rpc(
          "get_active_platform_promotions",
          params: <String, dynamic>{
            "p_surface": surface,
            "p_placement": placement,
            "p_limit": limit,
          },
        ),
      );
    } on PostgrestException catch (error) {
      if (!_isPromotionRpcCompatibilityError(error)) {
        rethrow;
      }
      return _decodeListRows(
        _client.rpc(
          "get_active_platform_promotions",
          params: <String, dynamic>{"p_placement": placement, "p_limit": limit},
        ),
      );
    }
  }

  Future<List<JsonMap>> fetchPromotionsForAdmin() async {
    return _decodeListRows(
      _client
          .from("platform_promotions")
          .select(
            "id, title, description, cta_label, target_url, placement, visibility_scope, start_at, end_at, display_order, is_active, created_at, target_region_id, target_district_id, target_ward_id, target_area_id, target_region:locations!platform_promotions_target_region_id_fkey(id, name, location_type), target_district:locations!platform_promotions_target_district_id_fkey(id, name, location_type), target_ward:locations!platform_promotions_target_ward_id_fkey(id, name, location_type), target_area:locations!platform_promotions_target_area_id_fkey(id, name, location_type), platform_promotion_media(id, media_type, media_path, thumbnail_path, display_order, is_primary)",
          )
          .order("display_order")
          .order("created_at", ascending: false),
    );
  }

  Future<void> savePromotion({
    String? promotionId,
    required String title,
    required String? description,
    required String? ctaLabel,
    required String? targetUrl,
    required String placement,
    required String visibilityScope,
    required int displayOrder,
    required bool isActive,
    required String? startAtIso,
    required String? endAtIso,
    required String targetRegionId,
    required String? targetDistrictId,
    required String? targetWardId,
    required String? targetAreaId,
    PlatformFile? mediaFile,
  }) async {
    final User user = _requireUser();
    final JsonMap payload = <String, dynamic>{
      "admin_id": user.id,
      "title": title,
      "description": description,
      "cta_label": ctaLabel,
      "target_url": targetUrl,
      "placement": placement,
      "visibility_scope": visibilityScope,
      "display_order": displayOrder,
      "is_active": isActive,
      "start_at": startAtIso == null || startAtIso.isEmpty ? null : startAtIso,
      "end_at": endAtIso == null || endAtIso.isEmpty ? null : endAtIso,
      "target_region_id": targetRegionId,
      "target_district_id": targetDistrictId,
      "target_ward_id": targetWardId,
      "target_area_id": targetAreaId,
    };

    final JsonMap promotion = promotionId == null
        ? await _client
              .from("platform_promotions")
              .insert(payload)
              .select("id")
              .single()
        : await _client
              .from("platform_promotions")
              .update(payload)
              .eq("id", promotionId)
              .select("id")
              .single();

    if (mediaFile == null || mediaFile.bytes == null) {
      return;
    }

    _validatePromotionMediaFile(mediaFile);

    final String promotionKey = promotion["id"] as String;
    final String fileName = _safeFileName(mediaFile.name);
    final String path = "platform-promotions/$promotionKey/$fileName";
    final String mediaType = _promotionMediaKind(mediaFile.name);
    final String contentType = _promotionMediaContentType(mediaFile.name);

    await _client.storage
        .from("platform-promotions")
        .uploadBinary(
          path,
          mediaFile.bytes!,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    await _client
        .from("platform_promotion_media")
        .delete()
        .eq("promotion_id", promotionKey)
        .eq("is_primary", true);

    await _client.from("platform_promotion_media").insert(<String, dynamic>{
      "promotion_id": promotionKey,
      "media_type": mediaType,
      "media_path": path,
      "thumbnail_path": null,
      "display_order": 0,
      "is_primary": true,
    });
  }

  Future<void> deletePromotion(String promotionId) async {
    final List<JsonMap> mediaRows = await _decodeListRows(
      _client
          .from("platform_promotion_media")
          .select("media_path, thumbnail_path")
          .eq("promotion_id", promotionId),
    );
    final List<String> paths = mediaRows
        .expand(
          (JsonMap row) => <String?>[
            row["media_path"] as String?,
            row["thumbnail_path"] as String?,
          ],
        )
        .whereType<String>()
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (paths.isNotEmpty) {
      await _client.storage.from("platform-promotions").remove(paths);
    }
    await _client.from("platform_promotions").delete().eq("id", promotionId);
  }

  Future<void> saveCategory({
    String? categoryId,
    required String name,
    required String slug,
    required String? description,
    required String? iconKey,
    required int displayOrder,
    required bool isActive,
    required int homeFeedWeight,
    required String fieldSchemaJson,
  }) async {
    final JsonMap payload = <String, dynamic>{
      "name": name,
      "slug": slug,
      "description": description,
      "icon_key": iconKey,
      "display_order": displayOrder,
      "is_active": isActive,
      "home_feed_weight": homeFeedWeight,
      "field_schema": jsonDecode(fieldSchemaJson),
    };
    if (categoryId == null) {
      await _client.from("asset_categories").insert(payload);
      return;
    }
    await _client.from("asset_categories").update(payload).eq("id", categoryId);
  }

  Future<List<JsonMap>> fetchLocations({
    required String? parentId,
    required LocationType type,
  }) async {
    dynamic query = _client
        .from("locations")
        .select("id, parent_id, name, location_type, latitude, longitude");
    query = parentId == null
        ? query.filter("parent_id", "is", "null")
        : query.eq("parent_id", parentId);
    return _decodeListRows(
      query
          .eq("location_type", type.storageValue)
          .eq("is_active", true)
          .order("name"),
    );
  }

  Future<List<JsonMap>> fetchMyListings({
    String search = "",
    String? category,
    String? status,
  }) async {
    final JsonMap agent = await _currentAgent();
    dynamic query = _client
        .from("listings")
        .select(
          "id, title, category_id, public_location_label, price_amount, price_period, status, availability_status, removed_from_market_at, removed_reason, created_at, asset_categories(id, name, slug)",
        )
        .eq("agent_id", agent["id"] as String)
        .order("created_at", ascending: false);
    if (search.isNotEmpty) {
      query = query.ilike("title", "%$search%");
    }
    if (category != null && category.isNotEmpty) {
      query = query.eq("category_id", category);
    }
    if (status != null && status.isNotEmpty) {
      query = query.eq("status", status);
    }
    final List<JsonMap> listings = await _decodeListRows(query);
    return _withInquiryCounts(listings);
  }

  Future<JsonMap> fetchListingDetail(String listingId) async {
    final JsonMap listing = await _client
        .from("listings")
        .select(
          "id, owner_id, category_id, listing_attributes, title, description, public_location_label, price_amount, price_period, deposit_required_amount, listing_rules, availability_status, status, location_id, removed_from_market_at, removed_reason, created_at, asset_categories(id, name, slug, field_schema)",
        )
        .eq("id", listingId)
        .single();

    final List<JsonMap> media = await _decodeListRows(
      _client
          .from("listing_media")
          .select(
            "id, media_type, storage_path, thumbnail_path, display_order, is_cover",
          )
          .eq("listing_id", listingId)
          .order("display_order"),
    );
    final JsonMap? privateLocation = await _fetchPrivateLocation(listingId);
    return <String, dynamic>{
      ...listing,
      "media": media,
      "private_location": privateLocation,
      "inquiry_count":
          (await _fetchInquiryCounts(<String>[listingId]))[listingId] ?? 0,
    };
  }

  Future<void> updateListingBasic({
    required String listingId,
    required String title,
    required String description,
    required double priceAmount,
    required String pricePeriod,
    required double depositAmount,
    required String rules,
    required String availabilityStatus,
  }) async {
    final JsonMap updates = <String, dynamic>{
      "title": title,
      "description": description,
      "price_amount": priceAmount,
      "price_period": pricePeriod,
      "deposit_required_amount": depositAmount,
      "listing_rules": rules,
      "availability_status": availabilityStatus,
    };
    await _client.from("listings").update(updates).eq("id", listingId);
  }

  Future<void> updateListingStatus({
    required String listingId,
    required String status,
  }) async {
    await _client
        .from("listings")
        .update(<String, dynamic>{"status": status})
        .eq("id", listingId);
  }

  Future<void> markListingAsRented(String listingId) async {
    await _client
        .from("listings")
        .update(<String, dynamic>{
          "status": "inactive",
          "availability_status": "rented",
          "removed_from_market_at": DateTime.now().toUtc().toIso8601String(),
          "removed_reason": "rented",
        })
        .eq("id", listingId);
  }

  Future<void> removeListingFromMarketplace(String listingId) async {
    await _client
        .from("listings")
        .update(<String, dynamic>{
          "status": "inactive",
          "removed_from_market_at": DateTime.now().toUtc().toIso8601String(),
          "removed_reason": "agent_removed",
        })
        .eq("id", listingId);
  }

  Future<void> reactivateListing(String listingId) async {
    await _client
        .from("listings")
        .update(<String, dynamic>{
          "status": "active",
          "availability_status": "available",
          "removed_from_market_at": null,
          "removed_reason": null,
        })
        .eq("id", listingId);
  }

  Future<void> deleteListing(String listingId) async {
    final FunctionResponse response = await _client.functions.invoke(
      "delete-empty-listing",
      body: <String, dynamic>{"listingId": listingId},
    );
    if (response.status >= 400) {
      throw StateError(
        (response.data as Map?)?["error"]?.toString() ?? "Delete failed",
      );
    }
  }

  Future<void> adminDeleteListing(
    String listingId, {
    bool confirmDeleteWithInquiries = false,
  }) async {
    final FunctionResponse response = await _client.functions.invoke(
      "admin-delete-listing",
      body: <String, dynamic>{
        "listingId": listingId,
        "confirm_delete_with_inquiries": confirmDeleteWithInquiries,
      },
    );
    if (response.status >= 400) {
      throw StateError(
        (response.data as Map?)?["error"]?.toString() ?? "Admin delete failed",
      );
    }
  }

  Future<void> submitDynamicListing({
    required String categoryId,
    required String? existingOwnerId,
    required String ownerName,
    required String ownerPhone,
    required String ownerNotes,
    required String title,
    required String description,
    required double priceAmount,
    required PricePeriod pricePeriod,
    required double depositAmount,
    required String rules,
    required String availabilityStatus,
    required String regionId,
    required String districtId,
    required String? wardId,
    required String? areaId,
    required String? streetId,
    required String exactAddress,
    required String latitude,
    required String longitude,
    required Map<String, dynamic> listingAttributes,
    required List<XFile> images,
    required XFile? video,
    required int coverImageIndex,
    UploadTaskController? uploadController,
    UploadProgressCallback? onProgress,
  }) async {
    final User user = _requireUser();
    final JsonMap agent = await _currentAgent();
    final String finalLocationId = streetId ?? areaId ?? wardId ?? districtId;
    final int totalMediaSteps = images.length + (video == null ? 0 : 1);
    final int totalSteps = 3 + totalMediaSteps;
    String? listingId;
    final List<String> uploadedPaths = <String>[];
    int completedSteps = 0;

    void markStep(String label, {bool canCancel = true}) {
      onProgress?.call(
        UploadProgressSnapshot(
          value: totalSteps == 0 ? 0 : completedSteps / totalSteps,
          label: label,
          canCancel: canCancel,
        ),
      );
    }

    markStep("Preparing listing upload...");
    _throwIfCancelled(uploadController);

    try {
      final String ownerId =
          existingOwnerId ??
          await _createOwner(
            agentId: agent["id"] as String,
            fullName: ownerName,
            phoneNumber: ownerPhone,
            notes: ownerNotes,
            locationId: finalLocationId,
          );
      completedSteps += 1;
      markStep("Owner details saved.");
      _throwIfCancelled(uploadController);

      final JsonMap listing = await _client
          .from("listings")
          .insert(<String, dynamic>{
            "agent_id": agent["id"],
            "owner_id": ownerId,
            "category_id": categoryId,
            "listing_attributes": listingAttributes,
            "title": title,
            "description": description,
            "location_id": finalLocationId,
            "price_amount": priceAmount,
            "price_period": pricePeriod.storageValue,
            "deposit_required_amount": depositAmount,
            "listing_rules": rules,
            "availability_status": availabilityStatus,
            "status": "active",
          })
          .select("id")
          .single();

      listingId = listing["id"] as String;
      completedSteps += 1;
      markStep("Listing record created.");
      _throwIfCancelled(uploadController);

      await _savePrivateLocation(
        listingId: listingId,
        exactAddress: exactAddress,
        latitude: latitude,
        longitude: longitude,
      );
      completedSteps += 1;
      markStep("Private location saved.");
      _throwIfCancelled(uploadController);

      await _uploadListingMedia(
        userId: user.id,
        listingId: listingId,
        images: images,
        video: video,
        coverImageIndex: coverImageIndex,
        uploadController: uploadController,
        onProgress: (UploadProgressSnapshot progress) {
          final double base = totalSteps == 0 ? 0 : completedSteps / totalSteps;
          final double stepScale = totalSteps == 0 ? 0 : 1 / totalSteps;
          onProgress?.call(
            UploadProgressSnapshot(
              value: (base + (progress.value * totalMediaSteps * stepScale))
                  .clamp(0.0, 1.0),
              label: progress.label,
              canCancel: progress.canCancel,
            ),
          );
        },
        uploadedPaths: uploadedPaths,
      );
      onProgress?.call(
        const UploadProgressSnapshot(
          value: 1,
          label: "Listing upload complete.",
          canCancel: false,
        ),
      );
    } on UploadCancelledException {
      if (uploadedPaths.isNotEmpty) {
        await _client.storage.from("listing-media").remove(uploadedPaths);
      }
      if (listingId != null) {
        try {
          await deleteListing(listingId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> submitListing({
    required ListingCategory category,
    required String? existingOwnerId,
    required String ownerName,
    required String ownerPhone,
    required String ownerNotes,
    required String title,
    required String description,
    required String publicLocationLabel,
    required double priceAmount,
    required PricePeriod pricePeriod,
    required double depositAmount,
    required String rules,
    required String availabilityStatus,
    required String? countryId,
    required String? regionId,
    required String? districtId,
    required String? wardId,
    required String? areaId,
    required String? streetId,
    required String exactAddress,
    required String latitude,
    required String longitude,
    required Map<String, dynamic> detailPayload,
    required List<XFile> images,
    required XFile? video,
    required int coverImageIndex,
  }) async {
    final User user = _requireUser();
    final JsonMap agent = await _currentAgent();
    final String categoryId = await _categoryIdForLegacyCategory(category);
    final String ownerId =
        existingOwnerId ??
        await _createOwner(
          agentId: agent["id"] as String,
          fullName: ownerName,
          phoneNumber: ownerPhone,
          notes: ownerNotes,
          locationId:
              streetId ??
              areaId ??
              wardId ??
              districtId ??
              regionId ??
              countryId,
        );

    final JsonMap listing = await _client
        .from("listings")
        .insert(<String, dynamic>{
          "agent_id": agent["id"],
          "owner_id": ownerId,
          "category_id": categoryId,
          "title": title,
          "description": description,
          "location_id":
              streetId ??
              areaId ??
              wardId ??
              districtId ??
              regionId ??
              countryId,
          "public_location_label": publicLocationLabel,
          "price_amount": priceAmount,
          "price_period": pricePeriod.storageValue,
          "deposit_required_amount": depositAmount,
          "listing_rules": rules,
          "availability_status": availabilityStatus,
          "status": "inactive",
        })
        .select("id")
        .single();

    final String listingId = listing["id"] as String;
    await _saveCategoryDetails(
      category: category,
      listingId: listingId,
      details: detailPayload,
    );
    await _savePrivateLocation(
      listingId: listingId,
      exactAddress: exactAddress,
      latitude: latitude,
      longitude: longitude,
    );

    await _uploadListingMedia(
      userId: user.id,
      listingId: listingId,
      images: images,
      video: video,
      coverImageIndex: coverImageIndex,
    );
  }

  Future<List<JsonMap>> fetchAgentBookings() async {
    final JsonMap agent = await _currentAgent();
    return _fetchBookings(
      queryBuilder: (dynamic query) =>
          query.eq("agent_id", agent["id"] as String),
    );
  }

  Future<List<JsonMap>> fetchAdminBookings() async {
    return _fetchBookings(queryBuilder: (dynamic query) => query);
  }

  Future<void> updateBookingStatus({
    required String bookingId,
    required BookingStatus status,
  }) async {
    await _client
        .from("booking_requests")
        .update(<String, dynamic>{"booking_status": status.storageValue})
        .eq("id", bookingId);
  }

  Future<List<JsonMap>> fetchNotifications() async {
    final User user = _requireUser();
    return _decodeListRows(
      _client
          .from("notifications")
          .select("id, title, body, created_at, read_at, type, payload")
          .eq("user_id", user.id)
          .order("created_at", ascending: false),
    );
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from("notifications")
        .update(<String, dynamic>{
          "read_at": DateTime.now().toUtc().toIso8601String(),
        })
        .eq("id", notificationId);
  }

  Future<List<JsonMap>> fetchPendingAgents() async {
    List<JsonMap> agents;
    try {
      agents = await _decodeListRows(
        _client
            .from("agents")
            .select(
              "id, profile_id, display_name, phone_number, contact_email, nida_number, public_location_label, profile_photo_path, verified_at, business_name, business_description, verification_status, account_status, activated_at, deactivated_at, deactivation_reason, created_at, profiles!inner(full_name, username, account_email, account_email_confirmed_at, preferred_language, phone_number, avatar_url), agent_documents(id, document_type, storage_path), agent_service_categories(category_id, is_primary, asset_categories(id, name, slug, icon_key))",
            )
            .order("created_at", ascending: false),
      );
    } on PostgrestException catch (error) {
      if (!_isManageIdentifierCompatibilityError(error)) {
        rethrow;
      }
      agents = await _decodeListRows(
        _client
            .from("agents")
            .select(
              "id, profile_id, display_name, phone_number, contact_email, nida_number, public_location_label, profile_photo_path, verified_at, business_name, business_description, verification_status, account_status, activated_at, deactivated_at, deactivation_reason, created_at, profiles!inner(full_name, phone_number, avatar_url), agent_documents(id, document_type, storage_path), agent_service_categories(category_id, is_primary, asset_categories(id, name, slug, icon_key))",
            )
            .order("created_at", ascending: false),
      );
    }
    return agents.map(_normalizeAdminAgent).toList();
  }

  Future<JsonMap> fetchAdminAgents({
    String searchText = "",
    String? accountStatus,
    String? verificationStatus,
    int limit = 40,
    int offset = 0,
  }) async {
    final String normalizedSearch = searchText.trim();
    final String? normalizedAccountStatus =
        accountStatus?.trim().isEmpty == true ? null : accountStatus?.trim();
    final String? normalizedVerificationStatus =
        verificationStatus?.trim().isEmpty == true
        ? null
        : verificationStatus?.trim();

    try {
      final List<JsonMap> rows = await _decodeListRows(
        _client.rpc(
          "search_admin_agents",
          params: <String, dynamic>{
            "p_search_text": normalizedSearch.isEmpty ? null : normalizedSearch,
            "p_account_status": normalizedAccountStatus,
            "p_verification_status": normalizedVerificationStatus,
            "p_limit": limit,
            "p_offset": offset,
          },
        ),
      );

      final List<JsonMap> items = rows.map((JsonMap row) {
        final JsonMap agent = <String, dynamic>{
          "id": row["agent_id"],
          "profile_id": row["profile_id"],
          "display_name": row["display_name"],
          "phone_number": row["phone_number"],
          "contact_email": row["contact_email"],
          "nida_number": row["nida_number"],
          "public_location_label": row["public_location_label"],
          "profile_photo_path": row["profile_photo_path"],
          "verified_at": row["verified_at"],
          "business_name": row["business_name"],
          "business_description": row["business_description"],
          "verification_status": row["verification_status"],
          "account_status": row["account_status"],
          "activated_at": row["activated_at"],
          "deactivated_at": row["deactivated_at"],
          "deactivation_reason": row["deactivation_reason"],
          "created_at": row["created_at"],
          "profiles": <String, dynamic>{
            "full_name": row["profile_full_name"],
            "username": row["profile_username"],
            "account_email": row["profile_account_email"],
            "account_email_confirmed_at":
                row["profile_account_email_confirmed_at"],
            "preferred_language": row["profile_preferred_language"],
            "phone_number": row["profile_phone_number"],
            "avatar_url": row["profile_avatar_url"],
          },
          "agent_documents":
              (row["agent_documents"] as List<dynamic>? ?? <dynamic>[]),
          "agent_service_categories":
              (row["agent_service_categories"] as List<dynamic>? ??
              <dynamic>[]),
        };
        return _normalizeAdminAgent(agent);
      }).toList();

      final int totalCount = rows.isEmpty
          ? 0
          : (rows.first["total_count"] as num?)?.toInt() ??
                int.tryParse(rows.first["total_count"]?.toString() ?? "") ??
                items.length;

      return <String, dynamic>{"items": items, "total_count": totalCount};
    } on PostgrestException catch (error) {
      if (!_isManageIdentifierCompatibilityError(error) &&
          (error.code ?? "") != "PGRST202") {
        rethrow;
      }

      final List<JsonMap> fallbackAgents = await fetchPendingAgents();
      final List<JsonMap> filtered = fallbackAgents.where((JsonMap agent) {
        final String nextAccountStatus =
            agent["account_status"] as String? ?? "";
        final String nextVerificationStatus =
            agent["verification_status"] as String? ?? "";
        if (normalizedAccountStatus != null &&
            nextAccountStatus != normalizedAccountStatus) {
          return false;
        }
        if (normalizedVerificationStatus != null &&
            nextVerificationStatus != normalizedVerificationStatus) {
          return false;
        }
        return _matchesAdminAgentSearch(agent, normalizedSearch);
      }).toList();
      final List<JsonMap> paged = filtered.skip(offset).take(limit).toList();
      return <String, dynamic>{"items": paged, "total_count": filtered.length};
    }
  }

  Future<List<JsonMap>> fetchProfilesAvailableForAgentCreation() async {
    List<JsonMap> profiles;
    try {
      profiles = await _decodeListRows(
        _client
            .from("profiles")
            .select("id, full_name, username, account_email, phone_number")
            .order("full_name"),
      );
    } on PostgrestException catch (error) {
      if (!_isManageIdentifierCompatibilityError(error)) {
        rethrow;
      }
      profiles = await _decodeListRows(
        _client
            .from("profiles")
            .select("id, full_name, phone_number")
            .order("full_name"),
      );
    }
    final Set<String> usedProfileIds =
        (await _decodeListRows(_client.from("agents").select("profile_id")))
            .map((JsonMap row) => row["profile_id"] as String?)
            .whereType<String>()
            .toSet();
    return profiles
        .where((JsonMap profile) => !usedProfileIds.contains(profile["id"]))
        .toList();
  }

  Future<void> createAgentFromProfile({
    required String profileId,
    required String displayName,
    required String phoneNumber,
    required String locationId,
    required String nidaNumber,
    required String primaryCategoryId,
    String? contactEmail,
    String? businessName,
    String? businessDescription,
  }) async {
    await _client.from("user_roles").upsert(<String, dynamic>{
      "profile_id": profileId,
      "role": "agent",
    }, onConflict: "profile_id,role");
    final JsonMap agent = await _client
        .from("agents")
        .insert(<String, dynamic>{
          "profile_id": profileId,
          "display_name": displayName,
          "phone_number": phoneNumber,
          "contact_email": contactEmail,
          "nida_number": nidaNumber.toUpperCase(),
          "location_id": locationId,
          "business_name": (businessName == null || businessName.trim().isEmpty)
              ? displayName
              : businessName.trim(),
          "business_description": businessDescription,
          "account_status": "inactive",
          "verification_status": "pending",
        })
        .select("id")
        .single();
    await _client.from("agent_service_categories").upsert(<String, dynamic>{
      "agent_id": agent["id"],
      "category_id": primaryCategoryId,
      "is_primary": true,
    }, onConflict: "agent_id,category_id");
  }

  Future<void> saveAgentCategoryAssignments({
    required String agentId,
    required List<String> categoryIds,
    required String primaryCategoryId,
  }) async {
    final Set<String> normalized = categoryIds
        .where((String value) => value.isNotEmpty)
        .toSet();
    normalized.add(primaryCategoryId);

    final List<JsonMap> existing = await _decodeListRows(
      _client
          .from("agent_service_categories")
          .select("category_id")
          .eq("agent_id", agentId),
    );
    final Set<String> existingIds = existing
        .map((JsonMap row) => row["category_id"] as String?)
        .whereType<String>()
        .toSet();

    final List<String> toDelete = existingIds.difference(normalized).toList();
    if (toDelete.isNotEmpty) {
      await _client
          .from("agent_service_categories")
          .delete()
          .eq("agent_id", agentId)
          .inFilter("category_id", toDelete);
    }

    await _client
        .from("agent_service_categories")
        .upsert(
          normalized
              .map(
                (String categoryId) => <String, dynamic>{
                  "agent_id": agentId,
                  "category_id": categoryId,
                  "is_primary": categoryId == primaryCategoryId,
                },
              )
              .toList(),
          onConflict: "agent_id,category_id",
        );
  }

  Future<void> createAgentAccount({
    required String username,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String locationId,
    required String nidaNumber,
    required String primaryCategoryId,
    String? businessName,
    String? businessDescription,
    String preferredLanguage = "sw",
  }) async {
    final FunctionResponse response = await _client.functions.invoke(
      "create-agent-account",
      body: <String, dynamic>{
        "username": username,
        "password": password,
        "full_name": fullName,
        "phone_number": phoneNumber,
        "location_id": locationId,
        "nida_number": nidaNumber,
        "preferred_language": preferredLanguage,
        "business_name": businessName ?? fullName,
        "business_description": businessDescription,
        "primary_category_id": primaryCategoryId,
      },
    );
    if (response.status >= 400) {
      throw StateError(
        (response.data as Map?)?["error"]?.toString() ??
            "Could not create agent account",
      );
    }
  }

  Future<List<JsonMap>> fetchCategoriesForAgentAssignment() async {
    if (_agentAssignmentCategoriesCache != null &&
        _cacheFresh(_agentAssignmentCategoriesCachedAt) &&
        _containsCategorySlug(_agentAssignmentCategoriesCache!, "apartment")) {
      return _cloneRows(_agentAssignmentCategoriesCache!);
    }
    final List<JsonMap> rows = await _decodeListRows(
      _client
          .from("asset_categories")
          .select(
            "id, name, slug, description, icon_key, display_order, is_active, home_feed_weight, field_schema",
          )
          .eq("is_active", true)
          .order("display_order")
          .order("name"),
    );

    final List<JsonMap> sorted = rows
        .where((JsonMap row) => row["slug"] is String && row["name"] is String)
        .map((JsonMap row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    sorted.sort((JsonMap a, JsonMap b) {
      final int displayCompare = ((a["display_order"] as num?)?.toInt() ?? 0)
          .compareTo((b["display_order"] as num?)?.toInt() ?? 0);
      if (displayCompare != 0) {
        return displayCompare;
      }
      return (a["name"] as String? ?? "").compareTo(b["name"] as String? ?? "");
    });

    _agentAssignmentCategoriesCache = _cloneRows(sorted);
    _agentAssignmentCategoriesCachedAt = DateTime.now();
    return sorted;
  }

  Future<void> updateAgentVerification({
    required String agentId,
    required String accountStatus,
    String? verificationStatus,
    String? note,
  }) async {
    final FunctionResponse response = await _client.functions.invoke(
      "verify-agent",
      body: <String, dynamic>{
        "agentId": agentId,
        "accountStatus": accountStatus,
        "verificationStatus": verificationStatus,
        "moderationNote": note,
        "deactivationReason": accountStatus == "active" ? null : note,
      },
    );
    if (response.status >= 400) {
      throw StateError(
        (response.data as Map?)?["error"]?.toString() ??
            "Could not update agent verification",
      );
    }
  }

  Future<List<JsonMap>> fetchAgentRegistrationLocations() async {
    final List<JsonMap> rows = (await fetchAgentLocationHierarchy())
        .where((JsonMap row) {
          final String? type = row["location_type"] as String?;
          return type == "region" ||
              type == "district" ||
              type == "ward" ||
              type == "area";
        })
        .map((JsonMap row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final Map<String, JsonMap> byId = <String, JsonMap>{
      for (final JsonMap row in rows) row["id"] as String: row,
    };
    return rows.map((JsonMap row) {
      final List<String> names = <String>[row["name"] as String? ?? "-"];
      String? cursor = row["parent_id"] as String?;
      while (cursor != null && names.length < 3) {
        final JsonMap? parent = byId[cursor];
        if (parent == null) {
          break;
        }
        names.add(parent["name"] as String? ?? "-");
        cursor = parent["parent_id"] as String?;
      }
      return <String, dynamic>{...row, "display_label": names.join(", ")};
    }).toList();
  }

  Future<List<JsonMap>> fetchAgentLocationHierarchy() async {
    if (_agentLocationHierarchyCache != null &&
        _cacheFresh(_agentLocationHierarchyCachedAt)) {
      return _cloneRows(_agentLocationHierarchyCache!);
    }
    final List<JsonMap> rows = await _decodePagedRows(
      (int from, int to) => _client
          .from("locations")
          .select("id, parent_id, name, location_type")
          .eq("is_active", true)
          .inFilter("location_type", <String>[
            "country",
            "region",
            "district",
            "ward",
            "area",
            "street",
          ])
          .order("name")
          .range(from, to),
    );
    _agentLocationHierarchyCache = _cloneRows(rows);
    _agentLocationHierarchyCachedAt = DateTime.now();
    return rows;
  }

  Future<String> resolveWardAreaLocation({
    required String? selectedAreaId,
    required String? wardId,
    required String manualAreaName,
  }) async {
    final String? trimmedSelectedAreaId = selectedAreaId?.trim().isEmpty == true
        ? null
        : selectedAreaId?.trim();
    if (trimmedSelectedAreaId != null) {
      return trimmedSelectedAreaId;
    }

    final String trimmedWardId = wardId?.trim() ?? "";
    if (trimmedWardId.isEmpty) {
      throw StateError("Choose a ward before choosing or creating an area.");
    }

    final String trimmedAreaName = manualAreaName.trim();
    if (trimmedAreaName.isEmpty) {
      throw StateError("Choose a saved area or type a new one.");
    }

    try {
      final List<dynamic> rows = await _client.rpc(
        "ensure_ward_area",
        params: <String, dynamic>{
          "p_ward_id": trimmedWardId,
          "p_area_name": trimmedAreaName,
        },
      );
      if (rows.isEmpty) {
        throw StateError(
          "We could not save that area right now. Please try again.",
        );
      }
      final JsonMap area = (rows.first as Map).cast<String, dynamic>();
      final String? areaId = area["id"] as String?;
      if (areaId == null || areaId.isEmpty) {
        throw StateError(
          "We could not save that area right now. Please try again.",
        );
      }
      if (area["created_new"] == true) {
        _invalidateLocationCaches();
      }
      return areaId;
    } on PostgrestException catch (error) {
      throw StateError(_friendlyAreaError(error));
    }
  }

  Future<JsonMap?> _resolveLoginIdentifier(String identifier) async {
    final String trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final List<dynamic> rows = await _client.rpc(
      "resolve_manage_login_identifier",
      params: <String, dynamic>{"p_identifier": trimmed},
    );
    if (rows.isEmpty) {
      return null;
    }
    return (rows.first as Map).cast<String, dynamic>();
  }

  bool _isManageIdentifierCompatibilityError(PostgrestException error) {
    final String code = error.code ?? "";
    final String message = error.message.toLowerCase();
    return code == "PGRST202" ||
        code == "PGRST204" ||
        code == "42703" ||
        message.contains("resolve_manage_login_identifier") ||
        message.contains("schema cache") ||
        message.contains("account_email") ||
        message.contains("account_email_confirmed_at") ||
        message.contains("username");
  }

  bool _isInternalManageAccountEmail(String email) {
    return email.trim().toLowerCase().endsWith("@agent.kodimali.local");
  }

  JsonMap _normalizeAdminAgent(JsonMap agent) {
    return <String, dynamic>{
      ...agent,
      "display_name":
          agent["display_name"] ??
          (agent["profiles"] as Map?)?["full_name"] ??
          agent["business_name"],
      "phone_number":
          agent["phone_number"] ?? (agent["profiles"] as Map?)?["phone_number"],
      "contact_email": agent["contact_email"],
      "nida_number": agent["nida_number"],
      "public_location_label": agent["public_location_label"],
      "profile_photo_path": agent["profile_photo_path"],
      "verified_at": agent["verified_at"],
      "profile_photo_url":
          _publicAgentPhotoUrl(agent["profile_photo_path"] as String?) ??
          ((agent["profiles"] as Map?)?["avatar_url"] as String?),
    };
  }

  bool _matchesAdminAgentSearch(JsonMap agent, String searchText) {
    final String normalizedSearch = searchText.trim().toLowerCase();
    if (normalizedSearch.isEmpty) {
      return true;
    }
    final Map<String, dynamic>? profile = (agent["profiles"] as Map?)
        ?.cast<String, dynamic>();
    final Iterable<String> haystack = <String>[
      agent["display_name"]?.toString() ?? "",
      agent["business_name"]?.toString() ?? "",
      agent["business_description"]?.toString() ?? "",
      agent["phone_number"]?.toString() ?? "",
      agent["contact_email"]?.toString() ?? "",
      agent["nida_number"]?.toString() ?? "",
      agent["public_location_label"]?.toString() ?? "",
      profile?["full_name"]?.toString() ?? "",
      profile?["username"]?.toString() ?? "",
      profile?["account_email"]?.toString() ?? "",
      profile?["phone_number"]?.toString() ?? "",
    ];
    for (final String value in haystack) {
      if (value.toLowerCase().contains(normalizedSearch)) {
        return true;
      }
    }
    return false;
  }

  String _friendlyAuthError(AuthException error) {
    final String message = error.message.trim();
    final String lower = message.toLowerCase();

    if (lower.contains("invalid login credentials") ||
        lower.contains("invalid_credentials")) {
      return "The username, phone number, email, or password you entered is incorrect.";
    }
    if (lower.contains("upstream request timeout") ||
        lower.contains("request timeout") ||
        lower.contains("timed out")) {
      return "Registration is taking too long on the server right now. Please try again shortly. If it keeps failing, contact admin because the Supabase Auth service or email delivery needs attention.";
    }
    if (lower.contains("email not confirmed") ||
        lower.contains("email_not_confirmed")) {
      return "This account email is not confirmed yet. Contact admin if the problem continues.";
    }
    if (lower.contains("user already registered") ||
        lower.contains("already registered")) {
      return "An account with those details already exists.";
    }
    if (lower.contains("password should be at least") ||
        lower.contains("password must be at least")) {
      return "Password must be at least 6 characters.";
    }
    if (lower.contains("same_password")) {
      return "Choose a different password from the current one.";
    }
    if (lower.contains("session_not_found") ||
        lower.contains("auth session missing")) {
      return "Your session expired. Please sign in again and retry.";
    }
    if (message.isEmpty) {
      return "We could not complete that request right now. Please try again.";
    }
    return message;
  }

  String _friendlyAreaError(PostgrestException error) {
    final String message = error.message.trim();
    final String lower = message.toLowerCase();

    if (lower.contains("100 saved areas")) {
      return "This ward already has the maximum 100 saved areas. Please choose one from the saved list.";
    }
    if (lower.contains(
      "ward is required before choosing or creating an area",
    )) {
      return "Choose a ward first before selecting or adding an area.";
    }
    if (lower.contains("ward was not found or is inactive")) {
      return "The selected ward is no longer available. Please choose it again.";
    }
    if (lower.contains("area name is required")) {
      return "Choose an existing area or type a new area name.";
    }
    if (lower.contains("agent location must be an active area")) {
      return "Please choose a valid area under the selected ward.";
    }
    if (lower.contains("location name is required")) {
      return "Enter a valid area name.";
    }
    if (lower.contains("column reference") &&
        lower.contains("id") &&
        lower.contains("ambiguous")) {
      return "We could not save that area because of a database conflict. Please try again after refreshing.";
    }
    if (lower.contains("ensure_ward_area")) {
      return "We could not save that area right now. Please try again.";
    }
    return message.isEmpty
        ? "We could not save that area right now. Please try again."
        : message;
  }

  Future<void> uploadAgentProfilePhoto({
    required XFile file,
    UploadTaskController? uploadController,
    UploadProgressCallback? onProgress,
  }) async {
    final JsonMap agent = await _currentAgent();
    final int bytes = await file.length();
    if (bytes > _agentPhotoMaxBytes) {
      throw StateError("Profile photo must be 5MB or smaller.");
    }
    final String extension = _fileExtension(file.name).toLowerCase();
    if (!<String>{"jpg", "jpeg", "png", "webp"}.contains(extension)) {
      throw StateError("Use JPG, PNG, or WebP for the profile photo.");
    }

    final String userId = _requireUser().id;
    final String nextPath =
        "$userId/profile-${DateTime.now().millisecondsSinceEpoch}.$extension";
    final String? previousPath = agent["profile_photo_path"] as String?;
    String? uploadedPath;
    try {
      onProgress?.call(
        const UploadProgressSnapshot(value: 0.1, label: "Preparing photo..."),
      );
      _throwIfCancelled(uploadController);
      final Uint8List data = await file.readAsBytes();
      onProgress?.call(
        const UploadProgressSnapshot(value: 0.4, label: "Uploading photo..."),
      );
      await _client.storage
          .from(_agentPhotoBucket)
          .uploadBinary(
            nextPath,
            data,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeForImageExtension(extension),
            ),
            retryController: uploadController?.retryController,
          );
      uploadedPath = nextPath;
      _throwIfCancelled(uploadController);
      onProgress?.call(
        const UploadProgressSnapshot(value: 0.8, label: "Saving profile..."),
      );
      await _client
          .from("agents")
          .update(<String, dynamic>{
            "profile_photo_path": nextPath,
            "profile_photo_updated_at": DateTime.now()
                .toUtc()
                .toIso8601String(),
          })
          .eq("id", agent["id"] as String);

      if (previousPath != null &&
          previousPath.isNotEmpty &&
          previousPath != nextPath) {
        await _client.storage.from(_agentPhotoBucket).remove(<String>[
          previousPath,
        ]);
      }
      onProgress?.call(
        const UploadProgressSnapshot(
          value: 1,
          label: "Profile photo updated.",
          canCancel: false,
        ),
      );
    } on UploadCancelledException {
      if (uploadedPath != null) {
        await _client.storage.from(_agentPhotoBucket).remove(<String>[
          uploadedPath,
        ]);
      }
      rethrow;
    }
  }

  Future<List<JsonMap>> fetchListingsForModeration() async {
    final List<JsonMap> listings = await _decodeListRows(
      _client
          .from("listings")
          .select(
            "id, title, category_id, public_location_label, status, removed_from_market_at, removed_reason, created_at, agent_id, asset_categories(id, name, slug)",
          )
          .order("created_at", ascending: false),
    );
    return _withInquiryCounts(listings);
  }

  Future<void> moderateListing({
    required String listingId,
    required String status,
    String? removedReason,
  }) async {
    final JsonMap updates = <String, dynamic>{
      "status": status,
      "removed_reason": removedReason,
      "removed_from_market_at": status == "active"
          ? null
          : DateTime.now().toUtc().toIso8601String(),
    };
    if (status == "active") {
      updates["published_at"] = DateTime.now().toUtc().toIso8601String();
      updates["availability_status"] = "available";
    }
    if (removedReason == "rented") {
      updates["availability_status"] = "rented";
    }
    await _client.from("listings").update(updates).eq("id", listingId);
  }

  Future<List<JsonMap>> fetchLocationsForAdmin() async {
    return _decodePagedRows(
      (int from, int to) => _client
          .from("locations")
          .select("id, parent_id, name, location_type, is_active, created_at")
          .order("location_type")
          .order("name")
          .range(from, to),
    );
  }

  Future<void> addLocation({
    required String name,
    required LocationType type,
    required String? parentId,
  }) async {
    await _client.from("locations").insert(<String, dynamic>{
      "name": name,
      "location_type": type.storageValue,
      "parent_id": parentId,
    });
    _invalidateLocationCaches();
  }

  Future<void> deleteLocation(String locationId) async {
    final String trimmedLocationId = locationId.trim();
    if (trimmedLocationId.isEmpty) {
      throw StateError("Location id is required.");
    }

    final int childCount = (await _decodeListRows(
      _client.from("locations").select("id").eq("parent_id", trimmedLocationId),
    )).length;
    if (childCount > 0) {
      throw StateError(
        "This location still has child locations. Delete the child locations first.",
      );
    }

    final int listingCount = (await _decodeListRows(
      _client
          .from("listings")
          .select("id")
          .eq("location_id", trimmedLocationId),
    )).length;
    if (listingCount > 0) {
      throw StateError(
        "This location is already used by active or historical listings, so it cannot be deleted.",
      );
    }

    final int agentCount = (await _decodeListRows(
      _client.from("agents").select("id").eq("location_id", trimmedLocationId),
    )).length;
    if (agentCount > 0) {
      throw StateError(
        "This location is already linked to one or more agent profiles, so it cannot be deleted.",
      );
    }

    final int ownerCount = (await _decodeListRows(
      _client.from("owners").select("id").eq("location_id", trimmedLocationId),
    )).length;
    if (ownerCount > 0) {
      throw StateError(
        "This location is already linked to owner records, so it cannot be deleted.",
      );
    }

    final int promotionCount = (await _decodeListRows(
      _client
          .from("platform_promotions")
          .select("id")
          .or(
            "target_region_id.eq.$trimmedLocationId,target_district_id.eq.$trimmedLocationId,target_ward_id.eq.$trimmedLocationId,target_area_id.eq.$trimmedLocationId",
          ),
    )).length;
    if (promotionCount > 0) {
      throw StateError(
        "This location is already targeted by platform promotions, so it cannot be deleted.",
      );
    }

    await _client.from("locations").delete().eq("id", trimmedLocationId);
    _invalidateLocationCaches();
  }

  Future<List<JsonMap>> fetchReports() async {
    return <JsonMap>[];
  }

  Future<List<JsonMap>> _fetchBookings({
    required dynamic Function(dynamic query) queryBuilder,
  }) async {
    final dynamic base = _client
        .from("booking_requests")
        .select(
          "id, listing_id, request_reference, customer_name, customer_phone_number, customer_email, requested_start_at, requested_end_at, guest_count, request_message, requested_service_codes, booking_status, created_at, listings!inner(title, asset_categories(name, slug))",
        );
    final dynamic filtered = queryBuilder(base);
    return _decodeListRows(filtered.order("created_at", ascending: false));
  }

  Future<Map<String, int>> _fetchInquiryCounts(
    Iterable<String> listingIds,
  ) async {
    final List<String> ids = listingIds
        .where((String id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return <String, int>{};
    }
    final List<JsonMap> rows = await _decodeListRows(
      _client.rpc(
        "get_listing_inquiry_counts",
        params: <String, dynamic>{"p_listing_ids": ids},
      ),
    );
    final Map<String, int> counts = <String, int>{};
    for (final JsonMap row in rows) {
      final String listingId = row["listing_id"] as String;
      counts[listingId] = (row["inquiry_count"] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<List<JsonMap>> _withInquiryCounts(List<JsonMap> listings) async {
    final Map<String, int> counts = await _fetchInquiryCounts(
      listings
          .map((JsonMap listing) => listing["id"] as String?)
          .whereType<String>(),
    );
    return listings
        .map(
          (JsonMap listing) => <String, dynamic>{
            ...listing,
            "inquiry_count": counts[listing["id"] as String] ?? 0,
          },
        )
        .toList();
  }

  Future<int> _count(PostgrestFilterBuilder<dynamic> query) async {
    final List<dynamic> result = await query;
    return result.length;
  }

  Future<JsonMap> _currentAgent() async {
    final JsonMap? agent = await _maybeCurrentAgent();
    if (agent == null) {
      throw StateError("Agent account not found");
    }
    return agent;
  }

  Future<JsonMap?> _maybeCurrentAgent() async {
    if (currentUser == null) {
      return null;
    }
    final List<dynamic> rows = await _client.rpc("get_my_agent_status");
    if (rows.isEmpty) {
      return null;
    }
    final JsonMap row = (rows.first as Map).cast<String, dynamic>();
    return <String, dynamic>{...row, "id": row["id"] ?? row["agent_id"]};
  }

  Future<JsonMap?> _myAgentStatus() async {
    final List<dynamic> rows = await _client.rpc("get_my_agent_status");
    if (rows.isEmpty) {
      return null;
    }
    return (rows.first as Map).cast<String, dynamic>();
  }

  Future<String?> _signPromotionMediaPath(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }
    return _client.storage
        .from("platform-promotions")
        .createSignedUrl(storagePath, _signedMediaUrlSeconds);
  }

  String? _publicAgentPhotoUrl(String? storagePath) {
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }
    return _client.storage.from(_agentPhotoBucket).getPublicUrl(storagePath);
  }

  String _fileExtension(String filename) {
    final int dotIndex = filename.lastIndexOf(".");
    if (dotIndex == -1 || dotIndex == filename.length - 1) {
      return "";
    }
    return filename.substring(dotIndex + 1);
  }

  String _contentTypeForImageExtension(String extension) {
    switch (extension) {
      case "jpg":
      case "jpeg":
        return "image/jpeg";
      case "png":
        return "image/png";
      case "webp":
        return "image/webp";
      case "gif":
        return "image/gif";
      case "heic":
        return "image/heic";
      case "heif":
        return "image/heif";
      default:
        return "application/octet-stream";
    }
  }

  String _contentTypeForVideoExtension(String extension) {
    switch (extension) {
      case "mp4":
        return "video/mp4";
      case "mov":
        return "video/quicktime";
      case "m4v":
        return "video/x-m4v";
      case "webm":
        return "video/webm";
      case "avi":
        return "video/x-msvideo";
      case "mkv":
        return "video/x-matroska";
      default:
        return "application/octet-stream";
    }
  }

  Future<String> _createOwner({
    required String agentId,
    required String fullName,
    required String phoneNumber,
    required String notes,
    required String? locationId,
  }) async {
    final JsonMap owner = await _client
        .from("owners")
        .insert(<String, dynamic>{
          "agent_id": agentId,
          "full_name": fullName,
          "phone_number": phoneNumber,
          "notes": notes,
          "location_id": locationId,
        })
        .select("id")
        .single();
    return owner["id"] as String;
  }

  Future<void> _saveCategoryDetails({
    required ListingCategory category,
    required String listingId,
    required Map<String, dynamic> details,
  }) async {
    switch (category) {
      case ListingCategory.house:
      case ListingCategory.office:
        await _client.from("property_details").insert(<String, dynamic>{
          "listing_id": listingId,
          ...details,
        });
        break;
      case ListingCategory.car:
      case ListingCategory.motorcycle:
        await _client.from("vehicle_details").insert(<String, dynamic>{
          "listing_id": listingId,
          ...details,
        });
        break;
      case ListingCategory.meetingHall:
      case ListingCategory.ceremonyHall:
        await _client.from("venue_details").insert(<String, dynamic>{
          "listing_id": listingId,
          ...details,
        });
        break;
      case ListingCategory.equipment:
      case ListingCategory.otherAsset:
        break;
    }
  }

  Future<void> _savePrivateLocation({
    required String listingId,
    required String exactAddress,
    required String latitude,
    required String longitude,
  }) async {
    if (exactAddress.isEmpty && latitude.isEmpty && longitude.isEmpty) {
      return;
    }
    final double? lat = double.tryParse(latitude);
    final double? lng = double.tryParse(longitude);
    await _client.from("listing_private_locations").upsert(<String, dynamic>{
      "listing_id": listingId,
      "exact_address": exactAddress.isEmpty ? null : exactAddress,
      "map_pin_latitude": lat,
      "map_pin_longitude": lng,
    });
  }

  Future<JsonMap?> _fetchPrivateLocation(String listingId) async {
    return await _client
        .from("listing_private_locations")
        .select("exact_address, map_pin_latitude, map_pin_longitude")
        .eq("listing_id", listingId)
        .maybeSingle();
  }

  Future<String> _categoryIdForLegacyCategory(ListingCategory category) async {
    final String slug = switch (category) {
      ListingCategory.house => "house",
      ListingCategory.car => "car",
      ListingCategory.motorcycle => "motorcycle",
      ListingCategory.office => "office",
      ListingCategory.meetingHall => "meeting-hall",
      ListingCategory.ceremonyHall => "ceremony-hall",
      ListingCategory.equipment => "equipment",
      ListingCategory.otherAsset => "other-asset",
    };
    final JsonMap? row = await _client
        .from("asset_categories")
        .select("id")
        .eq("slug", slug)
        .maybeSingle();
    if (row == null) {
      throw StateError("Asset category '$slug' was not found.");
    }
    return row["id"] as String;
  }

  Future<void> _uploadListingMedia({
    required String userId,
    required String listingId,
    required List<XFile> images,
    required XFile? video,
    required int coverImageIndex,
    UploadTaskController? uploadController,
    UploadProgressCallback? onProgress,
    List<String>? uploadedPaths,
  }) async {
    final int totalItems = images.length + (video == null ? 0 : 1);
    int completedItems = 0;

    void reportItem(String label) {
      onProgress?.call(
        UploadProgressSnapshot(
          value: totalItems == 0 ? 1 : completedItems / totalItems,
          label: label,
        ),
      );
    }

    for (int index = 0; index < images.length; index += 1) {
      _throwIfCancelled(uploadController);
      final XFile image = images[index];
      _validateListingImageFile(image);
      final String extension = _fileExtension(image.name).toLowerCase();
      final String fileName = _safeFileName(image.name);
      final String path = "$userId/$listingId/$fileName";
      reportItem("Uploading image ${index + 1} of $totalItems...");
      await _client.storage
          .from("listing-media")
          .uploadBinary(
            path,
            await image.readAsBytes(),
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeForImageExtension(extension),
            ),
            retryController: uploadController?.retryController,
          );
      uploadedPaths?.add(path);
      _throwIfCancelled(uploadController);
      await _client.from("listing_media").insert(<String, dynamic>{
        "listing_id": listingId,
        "media_type": "image",
        "storage_path": path,
        "display_order": index,
        "is_cover": index == coverImageIndex,
      });
      completedItems += 1;
      reportItem("Image ${index + 1} uploaded.");
    }
    if (video != null) {
      _throwIfCancelled(uploadController);
      final String extension = _fileExtension(video.name).toLowerCase();
      await _validateListingVideoFile(video);
      final String path = "$userId/$listingId/${_safeFileName(video.name)}";
      reportItem("Uploading video...");
      await _client.storage
          .from("listing-media")
          .uploadBinary(
            path,
            await video.readAsBytes(),
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentTypeForVideoExtension(extension),
            ),
            retryController: uploadController?.retryController,
          );
      uploadedPaths?.add(path);
      _throwIfCancelled(uploadController);
      await _client.from("listing_media").insert(<String, dynamic>{
        "listing_id": listingId,
        "media_type": "video",
        "storage_path": path,
        "display_order": images.length,
        "is_cover": false,
      });
      completedItems += 1;
      reportItem("Video uploaded.");
    }
  }

  void _validateListingImageFile(XFile file) {
    final String extension = _fileExtension(file.name).toLowerCase();
    if (!<String>{
      "jpg",
      "jpeg",
      "png",
      "webp",
      "gif",
      "heic",
      "heif",
    }.contains(extension)) {
      throw StateError(
        "Listing images must be JPG, PNG, WebP, GIF, HEIC, or HEIF.",
      );
    }
  }

  Future<void> _validateListingVideoFile(XFile file) async {
    final String extension = _fileExtension(file.name).toLowerCase();
    if (!<String>{
      "mp4",
      "mov",
      "m4v",
      "webm",
      "avi",
      "mkv",
    }.contains(extension)) {
      throw StateError(
        "Listing video must be MP4, MOV, M4V, WebM, AVI, or MKV.",
      );
    }
    final int bytes = await file.length();
    if (bytes > _listingVideoMaxBytes) {
      throw StateError("Listing video must be 30 MB or smaller.");
    }
  }

  void _throwIfCancelled(UploadTaskController? controller) {
    if (controller?.isCancelled == true) {
      throw const UploadCancelledException();
    }
  }

  AppRole _parseRole(String rawRole) => switch (rawRole) {
    "admin" => AppRole.admin,
    "agent" => AppRole.agent,
    _ => AppRole.customer,
  };

  bool _isPromotionRpcCompatibilityError(PostgrestException error) {
    return error.code == "PGRST202" ||
        error.code == "PGRST203" ||
        error.message.contains("schema cache") ||
        error.message.contains("Could not find the function") ||
        error.message.contains("Could not choose the best candidate function");
  }

  String _documentTypeFromName(String fileName) {
    final String lower = fileName.toLowerCase();
    if (lower.endsWith(".pdf")) {
      return "pdf";
    }
    if (lower.endsWith(".png") ||
        lower.endsWith(".jpg") ||
        lower.endsWith(".jpeg")) {
      return "image";
    }
    return "document";
  }

  void _validatePromotionMediaFile(PlatformFile file) {
    final String lower = file.name.toLowerCase();
    const Set<String> allowed = <String>{
      ".jpg",
      ".jpeg",
      ".png",
      ".webp",
      ".gif",
      ".heic",
      ".heif",
      ".mp4",
      ".mov",
      ".m4v",
      ".webm",
      ".avi",
      ".mkv",
    };
    final bool allowedExtension = allowed.any(lower.endsWith);
    if (!allowedExtension) {
      throw StateError(
        "Promotion media must be JPG, PNG, WebP, GIF, HEIC, HEIF, MP4, MOV, M4V, WebM, AVI, or MKV",
      );
    }
    if (file.size > _promotionMediaMaxBytes) {
      throw StateError("Promotion media must be 30 MB or smaller");
    }
  }

  String _promotionMediaKind(String fileName) {
    final String extension = _fileExtension(fileName).toLowerCase();
    return <String>{
          "mp4",
          "mov",
          "m4v",
          "webm",
          "avi",
          "mkv",
        }.contains(extension)
        ? "video"
        : "image";
  }

  String _promotionMediaContentType(String fileName) {
    final String extension = _fileExtension(fileName).toLowerCase();
    final String imageContentType = _contentTypeForImageExtension(extension);
    if (imageContentType != "application/octet-stream") {
      return imageContentType;
    }
    return _contentTypeForVideoExtension(extension);
  }

  String _safeFileName(String raw) {
    return raw.replaceAll(RegExp(r"[^A-Za-z0-9._-]"), "_");
  }

  User _requireUser() {
    final User? user = currentUser;
    if (user == null) {
      throw StateError("No authenticated user");
    }
    return user;
  }
}
