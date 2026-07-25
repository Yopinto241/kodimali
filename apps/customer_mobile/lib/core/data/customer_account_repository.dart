import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef CustomerJson = Map<String, dynamic>;

class CustomerAccountRepository {
  CustomerAccountRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
    String preferredLanguage = 'sw',
  }) {
    return _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: <String, dynamic>{
        'full_name': fullName.trim(),
        'phone_number': phoneNumber?.trim(),
        'preferred_language': preferredLanguage,
        'registration_source': 'customer_mobile',
        'register_as_agent': false,
      },
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<CustomerJson> fetchMyProfile() async {
    final User? user = currentUser;
    if (user == null) {
      return <String, dynamic>{};
    }
    try {
      final CustomerJson? profile = await _client
          .from('profiles')
          .select(
            'id, full_name, phone_number, avatar_url, preferred_language, account_email',
          )
          .eq('id', user.id)
          .maybeSingle();
      return profile ?? _profileFromUser(user);
    } catch (_) {
      return _profileFromUser(user);
    }
  }

  Future<List<CustomerJson>> fetchMyBookingRequests() async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'get_my_customer_booking_requests',
      );
      return (response as List<dynamic>).whereType<Map<dynamic, dynamic>>().map(
        (Map<dynamic, dynamic> raw) {
          final CustomerJson row = raw.cast<String, dynamic>();
          return <String, dynamic>{...row, 'id': row['booking_request_id']};
        },
      ).toList();
    } catch (error) {
      throw _friendlyError(
        error,
        'Your requests could not be loaded right now.',
      );
    }
  }

  Stream<List<CustomerJson>> watchMyBookingRequestChanges() {
    final User user = _requireUser();
    return _client
        .from('booking_requests')
        .stream(primaryKey: <String>['id'])
        .eq('customer_id', user.id)
        .order('created_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) => rows
              .map((Map<String, dynamic> row) => CustomerJson.from(row))
              .toList(),
        );
  }

  Stream<List<CustomerJson>> watchBookingRequestChanges(
    String bookingRequestId,
  ) {
    _requireUser();
    return _client
        .from('booking_requests')
        .stream(primaryKey: <String>['id'])
        .eq('id', bookingRequestId)
        .map(
          (List<Map<String, dynamic>> rows) => rows
              .map((Map<String, dynamic> row) => CustomerJson.from(row))
              .toList(),
        );
  }

  Future<CustomerJson?> fetchBookingRequest(String bookingRequestId) async {
    _requireUser();
    final List<CustomerJson> requests = await fetchMyBookingRequests();
    for (final CustomerJson request in requests) {
      if (request['id']?.toString() == bookingRequestId) {
        return request;
      }
    }
    return null;
  }

  Future<List<CustomerJson>> fetchBookingHistory(
    String bookingRequestId,
  ) async {
    _requireUser();
    try {
      return (await _client
              .from('booking_status_history')
              .select('id, status, reason, created_at')
              .eq('booking_request_id', bookingRequestId)
              .order('created_at'))
          .cast<CustomerJson>();
    } catch (_) {
      return <CustomerJson>[];
    }
  }

  Future<CustomerJson> claimGuestRequest(String requestReference) async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'claim_my_booking_request',
        params: <String, dynamic>{
          'p_request_reference': requestReference.trim(),
        },
      );
      final CustomerJson? row = _firstMap(response);
      if (row == null) {
        throw StateError('No matching request was found.');
      }
      return row;
    } catch (error) {
      throw _friendlyError(
        error,
        'We could not link that request to your account.',
      );
    }
  }

  Future<Set<String>> fetchRemoteSavedListingIds() async {
    final User? user = currentUser;
    if (user == null) {
      return <String>{};
    }
    try {
      final List<CustomerJson> rows =
          (await _client
                  .from('customer_saved_listings')
                  .select('listing_id')
                  .eq('customer_id', user.id)
                  .order('created_at', ascending: false))
              .cast<CustomerJson>();
      return rows
          .map((CustomerJson row) => row['listing_id'].toString())
          .toSet();
    } on PostgrestException catch (error) {
      if (_isCompatibilityError(error)) {
        return <String>{};
      }
      rethrow;
    }
  }

  Future<void> saveListing(String listingId) async {
    final User? user = currentUser;
    if (user == null) {
      return;
    }
    try {
      await _client.from('customer_saved_listings').upsert(<String, dynamic>{
        'customer_id': user.id,
        'listing_id': listingId,
      }, onConflict: 'customer_id,listing_id');
    } on PostgrestException catch (error) {
      if (!_isCompatibilityError(error)) {
        rethrow;
      }
    }
  }

  Future<void> removeSavedListing(String listingId) async {
    final User? user = currentUser;
    if (user == null) {
      return;
    }
    try {
      await _client
          .from('customer_saved_listings')
          .delete()
          .eq('customer_id', user.id)
          .eq('listing_id', listingId);
    } on PostgrestException catch (error) {
      if (!_isCompatibilityError(error)) {
        rethrow;
      }
    }
  }

  Future<void> recordListingView(String listingId) async {
    final User? user = currentUser;
    if (user == null) {
      return;
    }
    try {
      await _client.rpc(
        'record_listing_view',
        params: <String, dynamic>{'p_listing_id': listingId},
      );
    } on PostgrestException catch (error) {
      if (!_isCompatibilityError(error)) {
        rethrow;
      }
      try {
        await _client.from('customer_listing_views').upsert(<String, dynamic>{
          'customer_id': user.id,
          'listing_id': listingId,
          'last_viewed_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'customer_id,listing_id');
      } on PostgrestException catch (fallbackError) {
        if (!_isCompatibilityError(fallbackError)) {
          rethrow;
        }
      }
    }
  }

  Future<CustomerJson> getOrCreateConversation(String bookingRequestId) async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'get_or_create_booking_conversation',
        params: <String, dynamic>{'p_booking_request_id': bookingRequestId},
      );
      final CustomerJson? conversation = _firstMap(response);
      if (conversation == null) {
        throw StateError('Conversation could not be opened.');
      }
      return conversation;
    } catch (error) {
      throw _friendlyError(
        error,
        'Chat is not available for this request yet.',
      );
    }
  }

  Stream<List<CustomerJson>> watchMessages(String conversationId) {
    return _client
        .from('booking_messages')
        .stream(primaryKey: <String>['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map(
          (List<Map<String, dynamic>> rows) => rows
              .map((Map<String, dynamic> row) => CustomerJson.from(row))
              .toList(),
        );
  }

  Future<void> sendMessage({
    required String conversationId,
    required String body,
    required String clientMessageId,
  }) async {
    _requireUser();
    final String message = body.trim();
    if (message.isEmpty) {
      return;
    }
    try {
      await _client.rpc(
        'send_booking_message',
        params: <String, dynamic>{
          'p_conversation_id': conversationId,
          'p_body': message,
          'p_client_message_id': clientMessageId,
        },
      );
    } catch (error) {
      throw _friendlyError(error, 'Your message could not be sent.');
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    try {
      await _client.rpc(
        'mark_conversation_read',
        params: <String, dynamic>{'p_conversation_id': conversationId},
      );
    } catch (_) {
      // Read receipts must never stop the conversation from loading.
    }
  }

  Future<List<CustomerJson>> fetchViewingAppointments(
    String bookingRequestId,
  ) async {
    _requireUser();
    try {
      return (await _client
              .from('viewing_appointments')
              .select()
              .eq('booking_request_id', bookingRequestId)
              .order('created_at', ascending: false))
          .cast<CustomerJson>();
    } on PostgrestException catch (error) {
      if (_isCompatibilityError(error)) {
        return <CustomerJson>[];
      }
      throw _friendlyError(error, 'Viewing times could not be loaded.');
    }
  }

  Stream<List<CustomerJson>> watchViewingAppointmentChanges(
    String bookingRequestId,
  ) {
    _requireUser();
    return _client
        .from('viewing_appointments')
        .stream(primaryKey: <String>['id'])
        .eq('booking_request_id', bookingRequestId)
        .order('created_at', ascending: false)
        .map(
          (List<Map<String, dynamic>> rows) => rows
              .map((Map<String, dynamic> row) => CustomerJson.from(row))
              .toList(),
        );
  }

  Future<CustomerJson> proposeViewingAppointment({
    required String bookingRequestId,
    required DateTime scheduledStartAt,
    required DateTime scheduledEndAt,
    String? locationNote,
  }) async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'propose_viewing_appointment',
        params: <String, dynamic>{
          'p_booking_request_id': bookingRequestId,
          'p_scheduled_start_at': scheduledStartAt.toUtc().toIso8601String(),
          'p_scheduled_end_at': scheduledEndAt.toUtc().toIso8601String(),
          'p_location_note': locationNote?.trim(),
        },
      );
      final CustomerJson? appointment = _firstMap(response);
      if (appointment == null) {
        throw StateError('Viewing appointment could not be saved.');
      }
      return appointment;
    } catch (error) {
      throw _friendlyError(error, 'The viewing time could not be proposed.');
    }
  }

  Future<CustomerJson> respondToViewingAppointment({
    required String appointmentId,
    required String status,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
    String? responseNote,
  }) async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'respond_to_viewing_appointment',
        params: <String, dynamic>{
          'p_appointment_id': appointmentId,
          'p_status': status,
          'p_scheduled_start_at': scheduledStartAt?.toUtc().toIso8601String(),
          'p_scheduled_end_at': scheduledEndAt?.toUtc().toIso8601String(),
          'p_response_note': responseNote?.trim(),
        },
      );
      final CustomerJson? appointment = _firstMap(response);
      if (appointment == null) {
        throw StateError('Viewing appointment could not be updated.');
      }
      return appointment;
    } catch (error) {
      throw _friendlyError(
        error,
        'The viewing appointment could not be updated.',
      );
    }
  }

  Future<CustomerJson?> fetchMyReview(String bookingRequestId) async {
    _requireUser();
    try {
      return await _client
          .from('reviews')
          .select(
            'id, rating, comment, is_verified, moderation_status, created_at',
          )
          .eq('booking_request_id', bookingRequestId)
          .eq('customer_id', currentUser!.id)
          .maybeSingle();
    } on PostgrestException catch (error) {
      if (_isCompatibilityError(error)) {
        return null;
      }
      rethrow;
    }
  }

  Future<CustomerJson> submitReview({
    required String bookingRequestId,
    required int rating,
    String? comment,
  }) async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'submit_verified_review',
        params: <String, dynamic>{
          'p_booking_request_id': bookingRequestId,
          'p_rating': rating,
          'p_comment': comment?.trim(),
        },
      );
      final CustomerJson? review = _firstMap(response);
      if (review == null) {
        throw StateError('Review could not be saved.');
      }
      return review;
    } catch (error) {
      throw _friendlyError(
        error,
        'Only a completed rental can receive a review.',
      );
    }
  }

  Future<CustomerJson> requestAccountDeletion({String? reason}) async {
    _requireUser();
    try {
      final dynamic response = await _client.rpc(
        'request_my_account_deletion',
        params: <String, dynamic>{'p_reason': reason?.trim()},
      );
      final CustomerJson? request = _firstMap(response);
      if (request == null) {
        throw StateError('Account deletion request could not be saved.');
      }
      return request;
    } catch (error) {
      throw _friendlyError(
        error,
        'Your account deletion request could not be submitted.',
      );
    }
  }

  User _requireUser() {
    final User? user = currentUser;
    if (user == null) {
      throw StateError('Sign in to use this feature.');
    }
    return user;
  }

  CustomerJson _profileFromUser(User user) => <String, dynamic>{
    'id': user.id,
    'full_name': user.userMetadata?['full_name']?.toString() ?? '',
    'phone_number': user.userMetadata?['phone_number']?.toString(),
    'preferred_language':
        user.userMetadata?['preferred_language']?.toString() ?? 'sw',
    'account_email': user.email,
  };

  CustomerJson? _firstMap(dynamic response) {
    if (response is Map) {
      return response.cast<String, dynamic>();
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return (response.first as Map).cast<String, dynamic>();
    }
    return null;
  }

  bool _isCompatibilityError(PostgrestException error) {
    final String message = error.message.toLowerCase();
    return error.code == '42P01' ||
        error.code == '42703' ||
        error.code == 'PGRST202' ||
        message.contains('schema cache') ||
        message.contains('could not find the function') ||
        message.contains('does not exist');
  }

  StateError _friendlyError(Object error, String fallback) {
    final String raw = error
        .toString()
        .replaceFirst('PostgrestException(message: ', '')
        .replaceFirst('AuthApiException(message: ', '')
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .split(', code:')
        .first
        .trim();
    if (raw.isEmpty || raw.toLowerCase().contains('schema cache')) {
      return StateError(fallback);
    }
    return StateError(raw);
  }
}
