import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/manage_repository.dart';
import '../models/app_profile.dart';
import '../utils/user_facing_error.dart';

class AppController extends ChangeNotifier {
  AppController(this._repository);

  final ManageRepository _repository;
  StreamSubscription<AuthState>? _authSubscription;

  bool _initialized = false;
  bool _loading = false;
  Session? _session;
  AppProfile? _profile;
  String? _message;

  bool get initialized => _initialized;
  bool get loading => _loading;
  Session? get session => _session;
  User? get currentUser => _session?.user;
  AppProfile? get profile => _profile;
  String? get message => _message;
  bool get isSignedIn => currentUser != null;
  bool get isCustomerOnly => _profile?.isCustomerOnly ?? false;
  AppRole? get highestRole => _profile?.highestRole;
  String? get agentAccountStatus => _profile?.agentAccountStatus;
  bool get isAgentAccessBlocked =>
      highestRole == AppRole.agent && agentAccountStatus != "active";

  Future<void> initialize() async {
    _authSubscription ??= Supabase.instance.client.auth.onAuthStateChange
        .listen((AuthState state) async {
          _session = state.session;
          if (state.session == null) {
            _profile = null;
            _initialized = true;
            notifyListeners();
            return;
          }
          await refreshProfile();
        });

    _session = Supabase.instance.client.auth.currentSession;
    if (_session != null) {
      await refreshProfile();
    } else {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    final User? user = currentUser;
    if (user == null) {
      _profile = null;
      _initialized = true;
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      _profile = await _repository.fetchProfile(user.id);
      _message = null;
    } catch (error) {
      _message = userFacingError(error);
    } finally {
      _loading = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    _loading = true;
    notifyListeners();
    try {
      await _repository.signIn(identifier: identifier, password: password);
      _message = null;
    } finally {
      _loading = false;
      notifyListeners();
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
    _loading = true;
    notifyListeners();
    try {
      await _repository.registerAgentAccount(
        fullName: fullName,
        username: username,
        phoneNumber: phoneNumber,
        activationEmail: activationEmail,
        password: password,
        locationId: locationId,
        nidaNumber: nidaNumber,
        primaryCategoryId: primaryCategoryId,
        businessName: businessName,
        businessDescription: businessDescription,
        preferredLanguage: preferredLanguage,
      );
      _message =
          "Registration submitted successfully. Wait for admin approval before signing in as an agent.";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> sendPasswordReset(String identifier) async {
    _loading = true;
    notifyListeners();
    try {
      await _repository.sendPasswordReset(identifier);
      _message = "Password reset link has been sent to the recovery email.";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> changePassword(String newPassword) async {
    _loading = true;
    notifyListeners();
    try {
      await _repository.updatePassword(newPassword);
      _message = "Password updated successfully.";
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    _profile = null;
    _message = null;
    notifyListeners();
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
