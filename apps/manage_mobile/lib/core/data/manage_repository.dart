import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../media/listing_media_validator.dart';
import '../models/app_profile.dart';
import '../models/upload_task.dart';
import '../validation/listing_content_validator.dart';

typedef JsonMap = Map<String, dynamic>;

class ManageRepository {
  ManageRepository(this._client);

  final SupabaseClient _client;
  static const String _agentPhotoBucket = "agent-profile-photos";
  static const int _agentPhotoMaxBytes = 5 * 1024 * 1024;
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
      final List<JsonMap> rows = <JsonMap>[];
      for (final dynamic row in data) {
        if (row is! Map) {
          continue;
        }
        try {
          rows.add(Map<String, dynamic>.from(row));
        } catch (_) {
          // Ignore malformed rows instead of surfacing an opaque cast error.
        }
      }
      return rows;
    }
    if (data is Map) {
      try {
        return <JsonMap>[Map<String, dynamic>.from(data)];
      } catch (_) {
        return <JsonMap>[];
      }
    }
    return <JsonMap>[];
  }

  String? _nonEmptyString(dynamic value) {
    if (value is! String) {
      return null;
    }
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  JsonMap _requiredResponseMap(dynamic value, String message) {
    if (value is Map) {
      try {
        return Map<String, dynamic>.from(value);
      } catch (_) {
        // Fall through to the precise response-shape error below.
      }
    }
    throw StateError(message);
  }

  String _requiredStringField(
    Map<String, dynamic> row,
    String key,
    String message,
  ) {
    final String? value = _nonEmptyString(row[key]);
    if (value == null) {
      throw StateError(message);
    }
    return value;
  }

  String _requiredInputId(String? value, String message) {
    final String? normalized = _nonEmptyString(value);
    if (normalized == null) {
      throw StateError(message);
    }
    return normalized;
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
    final int scheduledViewings = await _count(
      _client
          .from("booking_requests")
          .select("id")
          .eq("agent_id", agentId)
          .eq("booking_status", "viewing_scheduled"),
    );
    final int completedRequests = await _count(
      _client
          .from("booking_requests")
          .select("id")
          .eq("agent_id", agentId)
          .eq("booking_status", "completed"),
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
      "scheduledViewings": scheduledViewings,
      "completedRequests": completedRequests,
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
    final int newRequests = await _count(
      _client.from("booking_requests").select("id").eq("booking_status", "new"),
    );
    final int completedRequests = await _count(
      _client
          .from("booking_requests")
          .select("id")
          .eq("booking_status", "completed"),
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
      "newRequests": newRequests,
      "completedRequests": completedRequests,
      "unreadNotifications": unreadNotifications,
    };
  }

  Future<JsonMap> fetchMarketplaceSettings() async {
    try {
      final JsonMap? row = await _client
          .from("marketplace_settings")
          .select("contact_payments_enabled, updated_at, updated_by")
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
    final String agentId = _requiredStringField(
      agent,
      "id",
      "Your agent account is missing its identifier. Sign in again.",
    );
    return _decodeListRows(
      _client
          .from("owners")
          .select("id, full_name, phone_number, notes, location_id, created_at")
          .eq("agent_id", agentId)
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

    final String agentId = _requiredStringField(
      agent,
      "id",
      "Your agent account is missing its identifier. Sign in again.",
    );

    final List<JsonMap> rows = await _decodeListRows(
      _client
          .from("agent_service_categories")
          .select(
            "category_id, is_primary, asset_categories!inner(id, name, slug, description, icon_key, display_order, is_active, home_feed_weight, field_schema)",
          )
          .eq("agent_id", agentId)
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
    required String? targetRegionId,
    required String? targetDistrictId,
    required String? targetWardId,
    required String? targetAreaId,
    PlatformFile? mediaFile,
  }) async {
    final User user = _requireUser();
    final String normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw StateError("Enter a promotion title.");
    }
    const Set<String> allowedPlacements = <String>{
      "global",
      "home_feed",
      "category_page",
      "listing_detail",
      "manage_dashboard",
      "website",
    };
    if (!allowedPlacements.contains(placement)) {
      throw StateError("Choose a valid promotion placement.");
    }
    const Set<String> allowedVisibilityScopes = <String>{
      "public",
      "manage",
      "admin",
      "all",
    };
    if (!allowedVisibilityScopes.contains(visibilityScope)) {
      throw StateError("Choose a valid promotion visibility scope.");
    }

    final DateTime? startAt = _parseOptionalPromotionDate(
      startAtIso,
      fieldLabel: "start date",
    );
    final DateTime? endAt = _parseOptionalPromotionDate(
      endAtIso,
      fieldLabel: "end date",
    );
    if (startAt != null && endAt != null && !endAt.isAfter(startAt)) {
      throw StateError("Promotion end date must be after its start date.");
    }

    final String? normalizedRegionId = _nullableTrim(targetRegionId);
    final String? normalizedDistrictId = _nullableTrim(targetDistrictId);
    final String? normalizedWardId = _nullableTrim(targetWardId);
    final String? normalizedAreaId = _nullableTrim(targetAreaId);
    if (normalizedRegionId == null &&
        (normalizedDistrictId != null ||
            normalizedWardId != null ||
            normalizedAreaId != null)) {
      throw StateError("Choose a region before a more specific location.");
    }
    if (normalizedDistrictId == null &&
        (normalizedWardId != null || normalizedAreaId != null)) {
      throw StateError("Choose a district before a ward or area.");
    }
    if (normalizedWardId == null && normalizedAreaId != null) {
      throw StateError("Choose a ward before an area.");
    }

    Uint8List? mediaBytes;
    if (mediaFile != null) {
      _validatePromotionMediaFile(mediaFile);
      mediaBytes = mediaFile.bytes;
      if (mediaBytes == null || mediaBytes.isEmpty) {
        throw StateError(
          "The selected promotion media could not be read. Choose it again from Gallery or Files.",
        );
      }
      if (mediaBytes.length > _promotionMediaMaxBytes) {
        throw StateError("Promotion media must be 30 MB or smaller.");
      }
    }

    final JsonMap payload = <String, dynamic>{
      "admin_id": user.id,
      "title": normalizedTitle,
      "description": _nullableTrim(description),
      "cta_label": _nullableTrim(ctaLabel),
      "target_url": _nullableTrim(targetUrl),
      "placement": placement,
      "visibility_scope": visibilityScope,
      "display_order": displayOrder,
      "is_active": isActive,
      "start_at": startAt?.toUtc().toIso8601String(),
      "end_at": endAt?.toUtc().toIso8601String(),
      "target_region_id": normalizedRegionId,
      "target_district_id": normalizedDistrictId,
      "target_ward_id": normalizedWardId,
      "target_area_id": normalizedAreaId,
    };

    JsonMap? savedPromotion;
    final bool creating = promotionId == null;
    try {
      savedPromotion = creating
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

      if (mediaFile != null && mediaBytes != null) {
        await _replacePromotionPrimaryMedia(
          promotionId: savedPromotion["id"] as String,
          mediaFile: mediaFile,
          mediaBytes: mediaBytes,
        );
      }
    } catch (error) {
      if (creating && savedPromotion?["id"] is String) {
        try {
          await _client
              .from("platform_promotions")
              .delete()
              .eq("id", savedPromotion!["id"] as String);
        } catch (_) {
          // The original error is more useful. A later admin refresh exposes
          // any row that could not be rolled back.
        }
      }
      if (error is PostgrestException) {
        throw StateError(_friendlyPromotionError(error));
      }
      if (error is StorageException) {
        throw StateError(
          "Promotion details could not be saved because the media upload failed. Check the connection and choose the file again.",
        );
      }
      rethrow;
    }
  }

  Future<void> _replacePromotionPrimaryMedia({
    required String promotionId,
    required PlatformFile mediaFile,
    required Uint8List mediaBytes,
  }) async {
    final List<JsonMap> existingRows = await _decodeListRows(
      _client
          .from("platform_promotion_media")
          .select("id, media_path, thumbnail_path")
          .eq("promotion_id", promotionId)
          .eq("is_primary", true),
    );
    final JsonMap? existing = existingRows.isEmpty ? null : existingRows.first;
    final String fileName = _safeFileName(mediaFile.name);
    final String path =
        "platform-promotions/$promotionId/${DateTime.now().microsecondsSinceEpoch}-$fileName";
    final JsonMap mediaPayload = <String, dynamic>{
      "promotion_id": promotionId,
      "media_type": _promotionMediaKind(mediaFile.name),
      "media_path": path,
      "thumbnail_path": null,
      "display_order": 0,
      "is_primary": true,
    };

    try {
      await _client.storage
          .from("platform-promotions")
          .uploadBinary(
            path,
            mediaBytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _promotionMediaContentType(mediaFile.name),
            ),
          );
    } catch (_) {
      try {
        await _client.storage.from("platform-promotions").remove(<String>[
          path,
        ]);
      } catch (_) {
        // Upload cleanup is best effort; the path is unique and is not linked
        // to a visible promotion media row.
      }
      rethrow;
    }

    try {
      if (existing?["id"] is String) {
        await _client
            .from("platform_promotion_media")
            .update(mediaPayload)
            .eq("id", existing!["id"] as String)
            .select("id")
            .single();
      } else {
        await _client
            .from("platform_promotion_media")
            .insert(mediaPayload)
            .select("id")
            .single();
      }
    } catch (_) {
      try {
        await _client.storage.from("platform-promotions").remove(<String>[
          path,
        ]);
      } catch (_) {
        // Keep the database error; an orphaned private object is safer than
        // deleting the media record that is still serving the promotion.
      }
      rethrow;
    }

    final List<String> replacedPaths = <String?>[
      existing?["media_path"] as String?,
      existing?["thumbnail_path"] as String?,
    ].whereType<String>().where((String item) => item != path).toSet().toList();
    if (replacedPaths.isNotEmpty) {
      try {
        await _client.storage.from("platform-promotions").remove(replacedPaths);
      } catch (_) {
        // The new media is already attached. Old private objects can be
        // cleaned separately without making the successful save look failed.
      }
    }
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
    final JsonMap? deleted = await _client
        .from("platform_promotions")
        .delete()
        .eq("id", promotionId)
        .select("id")
        .maybeSingle();
    if (deleted == null) {
      throw StateError(
        "Promotion was not found or your admin session cannot delete it.",
      );
    }
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from("platform-promotions").remove(paths);
      } catch (_) {
        // The database delete is authoritative. Do not tell the admin the
        // promotion still exists only because private-object cleanup failed.
      }
    }
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
    required List<Map<String, dynamic>> fieldSchema,
  }) async {
    final JsonMap payload = <String, dynamic>{
      "name": name,
      "slug": slug,
      "description": description,
      "icon_key": iconKey,
      "display_order": displayOrder,
      "is_active": isActive,
      "home_feed_weight": homeFeedWeight,
      "field_schema": fieldSchema,
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
    required JsonMap listingAttributes,
  }) async {
    final String normalizedListingId = _requiredInputId(
      listingId,
      'The listing identifier is missing. Refresh My Listings and retry.',
    );
    final String normalizedTitle = ListingContentValidator.requireValidTitle(
      title,
    );
    final String normalizedDescription =
        ListingContentValidator.requireValidDescription(description);
    if (priceAmount < 0) {
      throw StateError('Price cannot be negative.');
    }
    if (depositAmount < 0) {
      throw StateError('Deposit cannot be negative.');
    }
    final JsonMap updates = <String, dynamic>{
      "title": normalizedTitle,
      "description": normalizedDescription,
      "price_amount": priceAmount,
      "price_period": pricePeriod,
      "deposit_required_amount": depositAmount,
      "listing_rules": rules,
      "availability_status": availabilityStatus,
      "listing_attributes": listingAttributes,
    };
    await _client
        .from("listings")
        .update(updates)
        .eq("id", normalizedListingId);
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
    final String normalizedListingId = _requiredInputId(
      listingId,
      "The listing identifier is missing.",
    );
    final FunctionResponse response = await _client.functions.invoke(
      "delete-empty-listing",
      body: <String, dynamic>{"listingId": normalizedListingId},
    );
    if (response.status >= 400) {
      final dynamic data = response.data;
      throw StateError(
        data is Map
            ? data["error"]?.toString() ?? "Delete failed."
            : "Delete failed.",
      );
    }
    final JsonMap confirmation = _requiredResponseMap(
      response.data,
      "Supabase did not confirm that the incomplete listing was deleted.",
    );
    if (confirmation["success"] != true) {
      throw StateError(
        "Supabase did not confirm that the incomplete listing was deleted.",
      );
    }
    final String confirmedId = _requiredInputId(
      _nonEmptyString(confirmation["listingId"]) ??
          _nonEmptyString(confirmation["listing_id"]),
      "Supabase returned a delete confirmation without a listing identifier.",
    );
    if (confirmedId != normalizedListingId) {
      throw StateError("Supabase confirmed deletion for a different listing.");
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
    required bool videoIsCover,
    UploadTaskController? uploadController,
    UploadProgressCallback? onProgress,
  }) async {
    final String normalizedTitle = ListingContentValidator.requireValidTitle(
      title,
    );
    final String normalizedDescription =
        ListingContentValidator.requireValidDescription(description);
    await ListingMediaValidator.validateImages(images);
    if (coverImageIndex < 0 || coverImageIndex >= images.length) {
      throw StateError('Choose a valid cover image before publishing.');
    }
    if (video != null) {
      await ListingMediaValidator.validateCompressedVideo(video);
    }
    if (videoIsCover && video == null) {
      throw StateError('Choose a video before setting it as the cover.');
    }
    final String normalizedCategoryId = _requiredInputId(
      categoryId,
      "The selected category is missing its identifier. Refresh the form and "
      "choose the category again.",
    );
    _requiredInputId(regionId, "Choose a valid region before publishing.");
    _requiredInputId(districtId, "Choose a valid district before publishing.");
    final String normalizedWardId = _requiredInputId(
      wardId,
      "Choose a valid ward before publishing.",
    );
    final String? normalizedAreaId = _nonEmptyString(areaId);
    final String? normalizedStreetId = _nonEmptyString(streetId);
    final String? normalizedExistingOwnerId = _nonEmptyString(existingOwnerId);
    if (existingOwnerId != null && normalizedExistingOwnerId == null) {
      throw StateError(
        "The selected owner is missing its identifier. Choose the owner again.",
      );
    }
    _validatedPrivateCoordinates(latitude, longitude);
    final User user = _requireUser();
    final JsonMap agent = await _currentAgent();
    final String agentId = _requiredStringField(
      agent,
      "id",
      "Your agent account is missing its identifier. Sign in again.",
    );
    final String? agentStatus = _nonEmptyString(agent["account_status"]);
    if (agentStatus == null) {
      throw StateError(
        "Your agent account status is unavailable. Refresh the app or "
        "contact an administrator.",
      );
    }
    if (agentStatus != "active") {
      throw StateError(
        "Your agent account must be active before you can publish a listing.",
      );
    }
    final String finalLocationId =
        normalizedStreetId ?? normalizedAreaId ?? normalizedWardId;
    final int totalMediaSteps = images.length + (video == null ? 0 : 1);
    final int totalSteps = 4 + totalMediaSteps;
    String? listingId;
    bool listingInsertAttempted = false;
    final List<String> uploadedPaths = <String>[];
    int completedSteps = 0;
    String phase = 'saving owner details';

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
      phase = 'saving owner details';
      final String ownerId =
          normalizedExistingOwnerId ??
          await _createOwner(
            agentId: agentId,
            fullName: ownerName,
            phoneNumber: ownerPhone,
            notes: ownerNotes,
            locationId: finalLocationId,
          );
      completedSteps += 1;
      markStep("Owner details saved.");
      _throwIfCancelled(uploadController);

      phase = 'creating the private listing record';
      listingInsertAttempted = true;
      final dynamic listingResponse = await _client
          .from("listings")
          .insert(<String, dynamic>{
            "agent_id": agentId,
            "owner_id": ownerId,
            "category_id": normalizedCategoryId,
            "listing_attributes": listingAttributes,
            "title": normalizedTitle,
            "description": normalizedDescription,
            "location_id": finalLocationId,
            "price_amount": priceAmount,
            "price_period": pricePeriod.storageValue,
            "deposit_required_amount": depositAmount,
            "listing_rules": rules,
            "availability_status": availabilityStatus,
            // Keep incomplete media private until every upload succeeds.
            "status": "inactive",
          })
          .select("id")
          .single();
      final JsonMap listing = _requiredResponseMap(
        listingResponse,
        "The listing was saved but Supabase did not return its details. "
        "Refresh My Listings before retrying.",
      );
      listingId = _requiredStringField(
        listing,
        "id",
        "The listing was saved without an identifier. Refresh My Listings "
            "before retrying.",
      );
      completedSteps += 1;
      markStep("Listing record created.");
      _throwIfCancelled(uploadController);

      phase = 'saving the private location';
      await _savePrivateLocation(
        listingId: listingId,
        exactAddress: exactAddress,
        latitude: latitude,
        longitude: longitude,
      );
      completedSteps += 1;
      markStep("Private location saved.");
      _throwIfCancelled(uploadController);

      phase = 'uploading listing media';
      await _uploadListingMedia(
        userId: user.id,
        listingId: listingId,
        images: images,
        video: video,
        coverImageIndex: coverImageIndex,
        videoIsCover: videoIsCover,
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
      completedSteps += totalMediaSteps;
      phase = 'activating the completed listing';
      markStep('Activating completed listing...', canCancel: false);
      final dynamic activationResponse = await _client
          .from('listings')
          .update(<String, dynamic>{'status': 'active'})
          .eq('id', listingId)
          .select('id')
          .single();
      final JsonMap activatedListing = _requiredResponseMap(
        activationResponse,
        "Supabase did not confirm that the completed listing became active.",
      );
      final String activatedListingId = _requiredStringField(
        activatedListing,
        "id",
        "Supabase returned an activation response without a listing "
            "identifier.",
      );
      if (activatedListingId != listingId) {
        throw StateError(
          "Supabase confirmed a different listing during activation. "
          "Refresh My Listings before retrying.",
        );
      }
      completedSteps += 1;
      onProgress?.call(
        const UploadProgressSnapshot(
          value: 1,
          label: "Listing upload complete.",
          canCancel: false,
        ),
      );
    } on UploadCancelledException catch (error, stackTrace) {
      final bool fullyRemoved = await _rollbackFailedListingCreation(
        listingId: listingId,
        uploadedPaths: uploadedPaths,
        listingInsertAttempted:
            listingInsertAttempted && !_listingInsertDefinitelyRejected(error),
      );
      if (!fullyRemoved) {
        Error.throwWithStackTrace(
          StateError(
            "Upload was cancelled, but automatic cleanup was incomplete. "
            "Refresh My Listings; if an inactive draft remains, delete it "
            "before retrying.",
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      final bool fullyRemoved = await _rollbackFailedListingCreation(
        listingId: listingId,
        uploadedPaths: uploadedPaths,
        listingInsertAttempted:
            listingInsertAttempted && !_listingInsertDefinitelyRejected(error),
      );
      final String cleanupNote = fullyRemoved
          ? ''
          : ' Automatic cleanup was incomplete. Refresh My Listings before '
                'retrying; if an inactive draft remains, delete it first.';
      Error.throwWithStackTrace(
        StateError(
          'Could not finish $phase. ${_listingSubmissionError(error)}'
          '$cleanupNote',
        ),
        stackTrace,
      );
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
    required bool videoIsCover,
  }) async {
    final String normalizedTitle = ListingContentValidator.requireValidTitle(
      title,
    );
    final String normalizedDescription =
        ListingContentValidator.requireValidDescription(description);
    await ListingMediaValidator.validateImages(images);
    if (coverImageIndex < 0 || coverImageIndex >= images.length) {
      throw StateError("Choose a valid cover image before publishing.");
    }
    if (video != null) {
      await ListingMediaValidator.validateCompressedVideo(video);
    }
    if (videoIsCover && video == null) {
      throw StateError("Choose a video before setting it as the cover.");
    }
    _validatedPrivateCoordinates(latitude, longitude);

    final User user = _requireUser();
    final JsonMap agent = await _currentAgent();
    final String agentId = _requiredStringField(
      agent,
      "id",
      "Your agent account is missing its identifier. Sign in again.",
    );
    final String? agentStatus = _nonEmptyString(agent["account_status"]);
    if (agentStatus == null) {
      throw StateError(
        "Your agent account status is unavailable. Refresh the app or "
        "contact an administrator.",
      );
    }
    if (agentStatus != "active") {
      throw StateError(
        "Your agent account must be active before you can publish a listing.",
      );
    }
    final String? normalizedExistingOwnerId = _nonEmptyString(existingOwnerId);
    if (existingOwnerId != null && normalizedExistingOwnerId == null) {
      throw StateError(
        "The selected owner is missing its identifier. Choose the owner again.",
      );
    }
    final String? finalLocationId =
        _nonEmptyString(streetId) ??
        _nonEmptyString(areaId) ??
        _nonEmptyString(wardId) ??
        _nonEmptyString(districtId) ??
        _nonEmptyString(regionId) ??
        _nonEmptyString(countryId);
    if (finalLocationId == null) {
      throw StateError("Choose a valid listing location before publishing.");
    }
    String? listingId;
    bool listingInsertAttempted = false;
    final List<String> uploadedPaths = <String>[];
    String phase = "preparing the listing category";

    try {
      final String categoryId = await _categoryIdForLegacyCategory(category);
      phase = "saving owner details";
      final String ownerId =
          normalizedExistingOwnerId ??
          await _createOwner(
            agentId: agentId,
            fullName: ownerName,
            phoneNumber: ownerPhone,
            notes: ownerNotes,
            locationId: finalLocationId,
          );

      phase = "creating the private listing record";
      listingInsertAttempted = true;
      final dynamic listingResponse = await _client
          .from("listings")
          .insert(<String, dynamic>{
            "agent_id": agentId,
            "owner_id": ownerId,
            "category_id": categoryId,
            "title": normalizedTitle,
            "description": normalizedDescription,
            "location_id": finalLocationId,
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
      final JsonMap listing = _requiredResponseMap(
        listingResponse,
        "The listing was saved but Supabase did not return its details. "
        "Refresh My Listings before retrying.",
      );
      listingId = _requiredStringField(
        listing,
        "id",
        "The listing was saved without an identifier. Refresh My Listings "
            "before retrying.",
      );

      phase = "saving category details";
      await _saveCategoryDetails(
        category: category,
        listingId: listingId,
        details: detailPayload,
      );
      phase = "saving the private location";
      await _savePrivateLocation(
        listingId: listingId,
        exactAddress: exactAddress,
        latitude: latitude,
        longitude: longitude,
      );
      phase = "uploading listing media";
      await _uploadListingMedia(
        userId: user.id,
        listingId: listingId,
        images: images,
        video: video,
        coverImageIndex: coverImageIndex,
        videoIsCover: videoIsCover,
        uploadedPaths: uploadedPaths,
      );

      phase = "activating the completed listing";
      final dynamic activationResponse = await _client
          .from("listings")
          .update(<String, dynamic>{"status": "active"})
          .eq("id", listingId)
          .select("id")
          .single();
      final JsonMap activatedListing = _requiredResponseMap(
        activationResponse,
        "Supabase did not confirm that the completed listing became active.",
      );
      final String activatedListingId = _requiredStringField(
        activatedListing,
        "id",
        "Supabase returned an activation response without a listing "
            "identifier.",
      );
      if (activatedListingId != listingId) {
        throw StateError(
          "Supabase confirmed a different listing during activation. "
          "Refresh My Listings before retrying.",
        );
      }
    } catch (error, stackTrace) {
      final bool fullyRemoved = await _rollbackFailedListingCreation(
        listingId: listingId,
        uploadedPaths: uploadedPaths,
        listingInsertAttempted:
            listingInsertAttempted && !_listingInsertDefinitelyRejected(error),
      );
      final String cleanupNote = fullyRemoved
          ? ""
          : " Automatic cleanup was incomplete. Refresh My Listings before "
                "retrying; if an inactive draft remains, delete it first.";
      Error.throwWithStackTrace(
        StateError(
          "Could not finish $phase. ${_listingSubmissionError(error)}"
          "$cleanupNote",
        ),
        stackTrace,
      );
    }
  }

  Future<List<JsonMap>> fetchAgentBookings() async {
    final JsonMap agent = await _currentAgent();
    final List<JsonMap> bookings = await _fetchBookings(
      queryBuilder: (dynamic query) =>
          query.eq("agent_id", agent["id"] as String),
    );
    return bookings
        .map(
          (JsonMap booking) => <String, dynamic>{
            ...booking,
            "assigned_agent": <String, dynamic>{
              "id": agent["id"],
              "display_name":
                  agent["display_name"] ?? agent["business_name"] ?? "You",
              "business_name": agent["business_name"],
              "phone_number": agent["phone_number"],
            },
          },
        )
        .toList(growable: false);
  }

  Future<List<JsonMap>> fetchAdminBookings() async {
    final List<JsonMap> bookings = await _fetchBookings(
      queryBuilder: (dynamic query) => query,
    );
    final List<String> agentIds = bookings
        .map((JsonMap booking) => booking["agent_id"] as String?)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (agentIds.isEmpty) {
      return bookings;
    }

    final List<JsonMap> agents = await _decodeListRows(
      _client
          .from("agents")
          .select(
            "id, display_name, business_name, phone_number, contact_email, account_status, verification_status",
          )
          .inFilter("id", agentIds),
    );
    final Map<String, JsonMap> agentsById = <String, JsonMap>{
      for (final JsonMap agent in agents)
        if (agent["id"] is String) agent["id"] as String: agent,
    };
    return bookings
        .map(
          (JsonMap booking) => <String, dynamic>{
            ...booking,
            "assigned_agent": agentsById[booking["agent_id"]],
          },
        )
        .toList(growable: false);
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

  Future<JsonMap?> fetchBookingById(
    String bookingId, {
    required bool isAdmin,
  }) async {
    final List<JsonMap> bookings = await _fetchBookings(
      queryBuilder: (dynamic query) => query.eq("id", bookingId),
    );
    if (bookings.isEmpty) {
      return null;
    }
    final JsonMap booking = bookings.first;
    JsonMap? assignedAgent;
    if (isAdmin) {
      final String? agentId = booking["agent_id"] as String?;
      if (agentId != null) {
        assignedAgent = await _client
            .from("agents")
            .select(
              "id, display_name, business_name, phone_number, contact_email, account_status, verification_status",
            )
            .eq("id", agentId)
            .maybeSingle();
      }
    } else {
      assignedAgent = await _currentAgent();
    }
    return <String, dynamic>{...booking, "assigned_agent": assignedAgent};
  }

  Future<List<JsonMap>> fetchBookingStatusHistory(String bookingId) async {
    return _decodeListRows(
      _client
          .from("booking_status_history")
          .select("id, status, changed_by, reason, created_at")
          .eq("booking_request_id", bookingId)
          .order("created_at", ascending: false),
    );
  }

  Future<JsonMap?> getOrCreateBookingConversation(String bookingId) async {
    try {
      final dynamic response = await _client.rpc(
        "get_or_create_booking_conversation",
        params: <String, dynamic>{"p_booking_request_id": bookingId},
      );
      if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return null;
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<JsonMap>> fetchBookingMessages(String conversationId) async {
    try {
      return _decodeListRows(
        _client
            .from("booking_messages")
            .select(
              "id, conversation_id, sender_id, message_type, body, read_at, created_at, edited_at",
            )
            .eq("conversation_id", conversationId)
            .order("created_at"),
      );
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        return <JsonMap>[];
      }
      rethrow;
    }
  }

  Future<void> sendBookingMessage({
    required String conversationId,
    required String body,
  }) async {
    final String trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return;
    }
    try {
      await _client.rpc(
        "send_booking_message",
        params: <String, dynamic>{
          "p_conversation_id": conversationId,
          "p_body": trimmedBody,
        },
      );
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        throw StateError(
          "In-app chat is being activated on the server. Use Call or WhatsApp for this request for now.",
        );
      }
      rethrow;
    }
  }

  Future<void> markBookingConversationRead(String conversationId) async {
    try {
      await _client.rpc(
        "mark_conversation_read",
        params: <String, dynamic>{"p_conversation_id": conversationId},
      );
    } on PostgrestException catch (error) {
      if (!_isOptionalWorkflowCompatibilityError(error)) {
        rethrow;
      }
    }
  }

  Future<List<JsonMap>> fetchViewingAppointments(String bookingId) async {
    try {
      return _decodeListRows(
        _client
            .from("viewing_appointments")
            .select(
              "id, booking_request_id, listing_id, customer_id, agent_id, proposed_by, scheduled_start_at, scheduled_end_at, status, location_note, response_note, created_at, updated_at",
            )
            .eq("booking_request_id", bookingId)
            .order("created_at", ascending: false),
      );
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        return <JsonMap>[];
      }
      rethrow;
    }
  }

  Future<void> proposeViewingAppointment({
    required String bookingId,
    required DateTime startAt,
    required DateTime endAt,
    String? locationNote,
  }) async {
    if (!endAt.isAfter(startAt)) {
      throw StateError("The viewing end time must be after its start time.");
    }
    try {
      await _client.rpc(
        "propose_viewing_appointment",
        params: <String, dynamic>{
          "p_booking_request_id": bookingId,
          "p_scheduled_start_at": startAt.toUtc().toIso8601String(),
          "p_scheduled_end_at": endAt.toUtc().toIso8601String(),
          "p_location_note": locationNote?.trim().isEmpty == true
              ? null
              : locationNote?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        throw StateError(
          "Viewing appointments are being activated on the server. Contact the customer directly for now.",
        );
      }
      rethrow;
    }
  }

  Future<void> respondToViewingAppointment({
    required String appointmentId,
    required String status,
    DateTime? startAt,
    DateTime? endAt,
    String? responseNote,
  }) async {
    try {
      await _client.rpc(
        "respond_to_viewing_appointment",
        params: <String, dynamic>{
          "p_appointment_id": appointmentId,
          "p_status": status,
          "p_scheduled_start_at": startAt?.toUtc().toIso8601String(),
          "p_scheduled_end_at": endAt?.toUtc().toIso8601String(),
          "p_response_note": responseNote?.trim().isEmpty == true
              ? null
              : responseNote?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        throw StateError(
          "Viewing responses are being activated on the server. Please refresh and try again shortly.",
        );
      }
      rethrow;
    }
  }

  Future<JsonMap?> fetchBookingReview(String bookingId) async {
    try {
      final JsonMap? review = await _client
          .from("reviews")
          .select(
            "id, booking_request_id, rating, comment, is_verified, moderation_status, created_at",
          )
          .eq("booking_request_id", bookingId)
          .maybeSingle();
      return review;
    } on PostgrestException catch (error) {
      if (!_isOptionalWorkflowCompatibilityError(error)) {
        rethrow;
      }
      try {
        return await _client
            .from("reviews")
            .select("id, booking_request_id, rating, comment, created_at")
            .eq("booking_request_id", bookingId)
            .maybeSingle();
      } on PostgrestException catch (fallbackError) {
        if (_isOptionalWorkflowCompatibilityError(fallbackError)) {
          return null;
        }
        rethrow;
      }
    }
  }

  Future<List<JsonMap>> fetchAdminPaymentOperations({
    String? paymentStatus,
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      return _decodeListRows(
        _client.rpc(
          "get_admin_payment_operations",
          params: <String, dynamic>{
            "p_payment_status": paymentStatus,
            "p_limit": limit,
            "p_offset": offset,
          },
        ),
      );
    } on PostgrestException catch (error) {
      if (_isOptionalWorkflowCompatibilityError(error)) {
        return <JsonMap>[];
      }
      rethrow;
    }
  }

  Future<List<JsonMap>> fetchNotifications() async {
    final User user = _requireUser();
    return _decodeListRows(
      _client
          .from("notifications")
          .select(
            "id, booking_request_id, title, body, created_at, read_at, type, payload",
          )
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

  Future<List<JsonMap>> fetchAdminCustomerUsers({
    int limit = 100,
    int offset = 0,
  }) async {
    return _decodeListRows(
      _client.rpc(
        "get_admin_customer_users",
        params: <String, dynamic>{
          "p_offset": offset,
          "p_limit": limit.clamp(1, 100),
        },
      ),
    );
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
      final dynamic response = await _client.rpc(
        "ensure_ward_area",
        params: <String, dynamic>{
          "p_ward_id": trimmedWardId,
          "p_area_name": trimmedAreaName,
        },
      );
      if (response is! List) {
        throw StateError(
          "The location service returned an invalid response. Refresh the "
          "form and try again.",
        );
      }
      final List<dynamic> rows = response;
      if (rows.isEmpty) {
        throw StateError(
          "We could not save that area right now. Please try again.",
        );
      }
      final JsonMap area = _requiredResponseMap(
        rows.first,
        "The location service returned incomplete area details. Refresh the "
        "form and try again.",
      );
      final String areaId = _requiredStringField(
        area,
        "id",
        "The saved area is missing its identifier. Refresh the form and try "
            "again.",
      );
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
          "id, listing_id, customer_id, agent_id, request_reference, customer_name, customer_phone_number, customer_email, requested_start_at, requested_end_at, guest_count, request_message, requested_service_codes, booking_status, agent_response_due_at, first_agent_response_at, created_at, updated_at, listings!inner(title, asset_categories(name, slug))",
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
      throw StateError(
        "No agent account is linked to this sign-in. Complete agent "
        "registration or contact an administrator.",
      );
    }
    _requiredStringField(
      agent,
      "id",
      "Your agent account is missing its identifier. Sign out and sign in "
          "again; if this continues, contact an administrator.",
    );
    return agent;
  }

  Future<JsonMap?> _maybeCurrentAgent() async {
    if (currentUser == null) {
      return null;
    }
    final dynamic response = await _client.rpc("get_my_agent_status");
    if (response is! List) {
      throw StateError(
        "The agent account service returned an invalid response. Refresh "
        "the app and try again.",
      );
    }
    final List<dynamic> rows = response;
    if (rows.isEmpty) {
      return null;
    }
    final JsonMap row = _requiredResponseMap(
      rows.first,
      "The agent account service returned incomplete details. Refresh the "
      "app and try again.",
    );
    final String agentId = _requiredInputId(
      _nonEmptyString(row["id"]) ?? _nonEmptyString(row["agent_id"]),
      "Your agent account is missing its identifier. Sign out and sign in "
      "again; if this continues, contact an administrator.",
    );
    return <String, dynamic>{...row, "id": agentId};
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
    final String normalizedAgentId = _requiredInputId(
      agentId,
      "Your agent account is missing its identifier. Sign in again.",
    );
    final String normalizedName = fullName.trim();
    if (normalizedName.isEmpty) {
      throw StateError("Enter the owner's full name.");
    }
    final String normalizedPhone = phoneNumber.trim();
    if (normalizedPhone.isEmpty) {
      throw StateError("Enter the owner's phone number.");
    }
    final dynamic ownerResponse = await _client
        .from("owners")
        .insert(<String, dynamic>{
          "agent_id": normalizedAgentId,
          "full_name": normalizedName,
          "phone_number": normalizedPhone,
          "notes": notes.trim(),
          "location_id": _nonEmptyString(locationId),
        })
        .select("id")
        .single();
    final JsonMap owner = _requiredResponseMap(
      ownerResponse,
      "The owner was saved but Supabase did not return the owner details.",
    );
    return _requiredStringField(
      owner,
      "id",
      "The owner was saved without an identifier. Refresh the owner list "
          "before retrying.",
    );
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

  ({double? latitude, double? longitude}) _validatedPrivateCoordinates(
    String latitude,
    String longitude,
  ) {
    final String normalizedLatitude = latitude.trim();
    final String normalizedLongitude = longitude.trim();
    final bool hasLatitude = normalizedLatitude.isNotEmpty;
    final bool hasLongitude = normalizedLongitude.isNotEmpty;
    if (hasLatitude != hasLongitude) {
      throw StateError(
        "Enter both latitude and longitude, or leave both coordinates blank.",
      );
    }
    final double? lat = hasLatitude
        ? double.tryParse(normalizedLatitude)
        : null;
    final double? lng = hasLongitude
        ? double.tryParse(normalizedLongitude)
        : null;
    if (hasLatitude && (lat == null || lat < -90 || lat > 90)) {
      throw StateError("Latitude must be a number from -90 to 90.");
    }
    if (hasLongitude && (lng == null || lng < -180 || lng > 180)) {
      throw StateError("Longitude must be a number from -180 to 180.");
    }
    return (latitude: lat, longitude: lng);
  }

  Future<void> _savePrivateLocation({
    required String listingId,
    required String exactAddress,
    required String latitude,
    required String longitude,
  }) async {
    final String normalizedListingId = _requiredInputId(
      listingId,
      "The listing identifier is missing while saving its private location.",
    );
    final String normalizedAddress = exactAddress.trim();
    final ({double? latitude, double? longitude}) coordinates =
        _validatedPrivateCoordinates(latitude, longitude);
    if (normalizedAddress.isEmpty &&
        coordinates.latitude == null &&
        coordinates.longitude == null) {
      return;
    }
    final dynamic locationResponse = await _client
        .from("listing_private_locations")
        .upsert(<String, dynamic>{
          "listing_id": normalizedListingId,
          "exact_address": normalizedAddress.isEmpty ? null : normalizedAddress,
          "map_pin_latitude": coordinates.latitude,
          "map_pin_longitude": coordinates.longitude,
        })
        .select("listing_id")
        .single();
    final JsonMap savedLocation = _requiredResponseMap(
      locationResponse,
      "Supabase did not confirm the listing's private location.",
    );
    final String savedListingId = _requiredStringField(
      savedLocation,
      "listing_id",
      "Supabase returned a private location without its listing identifier.",
    );
    if (savedListingId != normalizedListingId) {
      throw StateError(
        "Supabase confirmed a private location for a different listing.",
      );
    }
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
    return _requiredStringField(
      row,
      "id",
      "Asset category '$slug' is missing its identifier. Ask an "
          "administrator to repair the category.",
    );
  }

  Future<bool> _rollbackFailedListingCreation({
    required String? listingId,
    required List<String> uploadedPaths,
    required bool listingInsertAttempted,
  }) async {
    bool mediaRemoved = true;
    final List<String> uniquePaths = uploadedPaths.toSet().toList();
    if (uniquePaths.isNotEmpty) {
      try {
        await _client.storage.from("listing-media").remove(uniquePaths);
      } catch (_) {
        mediaRemoved = false;
      }
    }

    if (listingId == null) {
      return mediaRemoved && !listingInsertAttempted;
    }

    try {
      await deleteListing(listingId);
      return mediaRemoved;
    } catch (_) {
      try {
        final JsonMap? remaining = await _client
            .from("listings")
            .select("id")
            .eq("id", listingId)
            .maybeSingle();
        if (remaining == null) {
          return mediaRemoved;
        }
      } catch (_) {
        // Continue with the safest fallback: keep any partial record private.
      }

      try {
        await _client
            .from("listings")
            .update(<String, dynamic>{"status": "inactive"})
            .eq("id", listingId)
            .select("id")
            .single();
      } catch (_) {
        // The caller reports cleanup as incomplete. Do not mask the original
        // create/upload failure with a second database error.
      }
      return false;
    }
  }

  String _listingSubmissionError(Object error) {
    String message;
    if (error is PostgrestException) {
      message = error.message;
    } else if (error is StorageException) {
      message = error.message;
    } else if (error is AuthException) {
      message = error.message;
    } else {
      message = error.toString();
    }

    message = message
        .replaceAll("Bad state: ", "")
        .replaceAll("Exception: ", "")
        .trim();
    final String lower = message.toLowerCase();
    if (lower.contains('listings_description_check')) {
      return 'Description must have at least '
          '${ListingContentValidator.minimumDescriptionCharacters} characters.';
    }
    if (lower.contains('listings_title_check')) {
      return 'Title must contain between '
          '${ListingContentValidator.minimumTitleCharacters} and '
          '${ListingContentValidator.maximumTitleCharacters} characters.';
    }
    if (lower.contains("failed host lookup") ||
        lower.contains("socketexception") ||
        lower.contains("connection reset") ||
        lower.contains("network is unreachable") ||
        lower.contains("clientexception")) {
      return "Check your internet connection and try again.";
    }
    if (lower.contains("jwt") ||
        lower.contains("unauthorized") ||
        lower.contains("not authenticated")) {
      return "Your session may have expired. Sign in again and retry.";
    }
    if (lower.contains("payload too large") ||
        lower.contains("maximum allowed size") ||
        lower.contains("exceeded the maximum")) {
      return "A selected file exceeded the 30 MB server limit. Choose the "
          "file again and retry.";
    }
    if (lower.contains("row-level security") ||
        lower.contains("permission denied")) {
      return "Your account is not allowed to complete this listing action. "
          "Refresh your session or contact an administrator.";
    }
    if (message.isEmpty) {
      return "Check the connection and try again.";
    }
    return message.endsWith(".") ? message : "$message.";
  }

  bool _listingInsertDefinitelyRejected(Object error) {
    // A check-constraint response means PostgreSQL rejected the INSERT and no
    // listing row exists. Do not report cleanup as uncertain in this case.
    return error is PostgrestException && error.code == '23514';
  }

  Future<void> _uploadListingMedia({
    required String userId,
    required String listingId,
    required List<XFile> images,
    required XFile? video,
    required int coverImageIndex,
    required bool videoIsCover,
    UploadTaskController? uploadController,
    UploadProgressCallback? onProgress,
    List<String>? uploadedPaths,
  }) async {
    await ListingMediaValidator.validateImages(images);
    if (coverImageIndex < 0 || coverImageIndex >= images.length) {
      throw StateError("Choose a valid cover image before publishing.");
    }
    if (video != null) {
      await ListingMediaValidator.validateCompressedVideo(video);
    }

    final int totalItems = images.length + (video == null ? 0 : 1);
    final int uploadNonce = DateTime.now().microsecondsSinceEpoch;
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
      final String extension = ListingMediaValidator.extensionOf(image.name);
      final String path =
          "$userId/$listingId/image-$uploadNonce-${index + 1}.$extension";
      reportItem("Uploading image ${index + 1} of ${images.length}...");
      try {
        await _client.storage
            .from("listing-media")
            .uploadBinary(
              path,
              await image.readAsBytes(),
              fileOptions: FileOptions(
                upsert: false,
                contentType: _contentTypeForImageExtension(extension),
              ),
              retryController: uploadController?.retryController,
            );
      } catch (error, stackTrace) {
        if (uploadController?.isCancelled == true) {
          throw const UploadCancelledException();
        }
        Error.throwWithStackTrace(
          StateError(
            "Image ${index + 1} could not be uploaded. "
            "${_listingSubmissionError(error)}",
          ),
          stackTrace,
        );
      }
      uploadedPaths?.add(path);
      _throwIfCancelled(uploadController);
      try {
        await _client.from("listing_media").insert(<String, dynamic>{
          "listing_id": listingId,
          "media_type": "image",
          "storage_path": path,
          "display_order": videoIsCover ? index + 1 : index,
          "is_cover": !videoIsCover && index == coverImageIndex,
        });
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          StateError(
            "Image ${index + 1} was uploaded but could not be attached to "
            "the listing. ${_listingSubmissionError(error)}",
          ),
          stackTrace,
        );
      }
      completedItems += 1;
      reportItem("Image ${index + 1} uploaded.");
    }
    if (video != null) {
      _throwIfCancelled(uploadController);
      final String path = "$userId/$listingId/video-$uploadNonce.mp4";
      reportItem("Uploading video...");
      try {
        await _client.storage
            .from("listing-media")
            .uploadBinary(
              path,
              await video.readAsBytes(),
              fileOptions: const FileOptions(
                upsert: false,
                contentType: "video/mp4",
              ),
              retryController: uploadController?.retryController,
            );
      } catch (error, stackTrace) {
        if (uploadController?.isCancelled == true) {
          throw const UploadCancelledException();
        }
        Error.throwWithStackTrace(
          StateError(
            "The compressed video could not be uploaded. "
            "${_listingSubmissionError(error)}",
          ),
          stackTrace,
        );
      }
      uploadedPaths?.add(path);
      _throwIfCancelled(uploadController);
      try {
        await _client.from("listing_media").insert(<String, dynamic>{
          "listing_id": listingId,
          "media_type": "video",
          "storage_path": path,
          "display_order": videoIsCover ? 0 : images.length,
          "is_cover": videoIsCover,
        });
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          StateError(
            "The video was uploaded but could not be attached to the listing. "
            "${_listingSubmissionError(error)}",
          ),
          stackTrace,
        );
      }
      completedItems += 1;
      reportItem("Video uploaded.");
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

  String? _nullableTrim(String? value) {
    final String normalized = value?.trim() ?? "";
    return normalized.isEmpty ? null : normalized;
  }

  DateTime? _parseOptionalPromotionDate(
    String? value, {
    required String fieldLabel,
  }) {
    final String? normalized = _nullableTrim(value);
    if (normalized == null) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(normalized);
    if (parsed == null) {
      throw StateError(
        "Enter a valid promotion $fieldLabel, for example 2026-07-20T10:00:00+03:00.",
      );
    }
    return parsed;
  }

  String _friendlyPromotionError(PostgrestException error) {
    final String message = error.message.trim();
    final String lower = message.toLowerCase();
    if (lower.contains("target district must belong") ||
        lower.contains("target ward must belong") ||
        lower.contains("target area must belong") ||
        lower.contains("promotion target region") ||
        lower.contains("promotion target district") ||
        lower.contains("promotion target ward") ||
        lower.contains("promotion target area")) {
      return "The selected promotion locations no longer form a valid region, district, ward, and area chain. Choose the location again.";
    }
    if (lower.contains("invalid input syntax for type timestamp") ||
        lower.contains("date/time field value out of range")) {
      return "Promotion start or end time is invalid. Use a complete ISO date and time.";
    }
    if (error.code == "42501" ||
        lower.contains("row-level security") ||
        lower.contains("permission denied")) {
      return "Your admin session cannot save promotions. Sign in again and confirm that this account still has the admin role.";
    }
    if (error.code == "PGRST116") {
      return "The promotion no longer exists or could not be saved. Refresh the list and try again.";
    }
    return message.isEmpty
        ? "Promotion could not be saved. Please try again."
        : message;
  }

  bool _isOptionalWorkflowCompatibilityError(PostgrestException error) {
    final String code = error.code ?? "";
    final String message = error.message.toLowerCase();
    return code == "PGRST202" ||
        code == "PGRST204" ||
        code == "42P01" ||
        code == "42703" ||
        code == "42883" ||
        message.contains("schema cache") ||
        message.contains("could not find the function") ||
        message.contains("does not exist");
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
        "Promotion media must be JPG, PNG, WebP, GIF, HEIC, HEIF, MP4, MOV, M4V, WebM, AVI, or MKV.",
      );
    }
    if (file.size <= 0) {
      throw StateError("Promotion media file is empty. Choose another file.");
    }
    if (file.size > _promotionMediaMaxBytes) {
      throw StateError("Promotion media must be 30 MB or smaller.");
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
