import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CustomerActivityJson = Map<String, dynamic>;

/// Keeps favourites and recently viewed listings useful before a customer
/// creates an account. Authenticated copies are synchronized by the account
/// repository, while this local snapshot remains the offline source of truth.
class CustomerActivityStore extends ChangeNotifier {
  CustomerActivityStore._();

  static final CustomerActivityStore instance = CustomerActivityStore._();

  String _scope = 'guest';
  String? get userId => _scope == 'guest' ? null : _scope;
  String get _savedKey => 'customer_activity_v2|$_scope|saved';
  String get _recentKey => 'customer_activity_v2|$_scope|recent';
  String get _pendingKey => 'customer_activity_v2|$_scope|pending';
  final Map<String, bool> _pending = {};
  Map<String, bool> get pendingChanges => Map.unmodifiable(_pending);
  bool get hasGuestActivity => _decodeSnapshots(
    _preferences?.getString('customer_activity_v2|guest|saved'),
  ).isNotEmpty;

  Future<void> switchAccount(String? user) async {
    final scope = user ?? 'guest';
    if (_scope == scope) return;
    _scope = scope;
    _loadScope();
    notifyListeners();
  }

  void _loadScope() {
    final prefs = _preferences;
    _saved
      ..clear()
      ..addAll(_decodeSnapshots(prefs?.getString(_savedKey)));
    _recent
      ..clear()
      ..addAll(_decodeSnapshots(prefs?.getString(_recentKey)));
    _pending
      ..clear()
      ..addAll(
        Map<String, bool>.from(
          jsonDecode(prefs?.getString(_pendingKey) ?? '{}') as Map,
        ),
      );
  }

  Future<void> mergeGuestActivity() async {
    if (userId == null) return;
    final rows = _decodeSnapshots(
      _preferences?.getString('customer_activity_v2|guest|saved'),
    );
    for (final row in rows) {
      final id = _listingId(row);
      if (!isSaved(id)) _saved.add(row);
      _pending[id] = true;
    }
    final savedKey = _savedKey;
    final pendingKey = _pendingKey;
    final savedJson = jsonEncode(_saved);
    final pendingJson = jsonEncode(_pending);
    await _preferences?.setString(savedKey, savedJson);
    await _preferences?.setString(pendingKey, pendingJson);
    await _preferences?.remove('customer_activity_v2|guest|saved');
    notifyListeners();
  }

  Future<void> acknowledgeSaved(
    String id,
    bool saved, {
    required String? forUser,
  }) async {
    if (forUser != userId || _pending[id] != saved) return;
    _pending.remove(id);
    await _preferences?.setString(_pendingKey, jsonEncode(_pending));
  }

  static const int _maximumRecentItems = 20;

  SharedPreferences? _preferences;
  final List<CustomerActivityJson> _saved = <CustomerActivityJson>[];
  final List<CustomerActivityJson> _recent = <CustomerActivityJson>[];

  List<CustomerActivityJson> get savedListings =>
      List<CustomerActivityJson>.unmodifiable(_saved);

  List<CustomerActivityJson> get recentlyViewed =>
      List<CustomerActivityJson>.unmodifiable(_recent);

  Set<String> get savedListingIds =>
      _saved.map(_listingId).where((String id) => id.isNotEmpty).toSet();

  Future<void> initialize(
    SharedPreferences preferences, {
    String? userId,
  }) async {
    _preferences = preferences;
    _scope = userId ?? 'guest';
    // v1 is deliberately retained but never attributed to a different account:
    // old device-global data has no trustworthy owner. Remote favourites remain.
    _loadScope();
  }

  bool isSaved(String listingId) =>
      _saved.any((CustomerActivityJson item) => _listingId(item) == listingId);

  Future<bool> toggleSaved(CustomerActivityJson listing) async {
    final CustomerActivityJson snapshot = _normalizeListing(listing);
    final String listingId = _listingId(snapshot);
    if (listingId.isEmpty) {
      return false;
    }
    final int existingIndex = _saved.indexWhere(
      (CustomerActivityJson item) => _listingId(item) == listingId,
    );
    final bool saved;
    if (existingIndex >= 0) {
      _saved.removeAt(existingIndex);
      saved = false;
    } else {
      _saved.insert(0, snapshot);
      saved = true;
    }
    _pending[listingId] = saved;
    final savedKey = _savedKey;
    final pendingKey = _pendingKey;
    final savedJson = jsonEncode(_saved);
    final pendingJson = jsonEncode(_pending);
    await _preferences?.setString(pendingKey, pendingJson);
    await _preferences?.setString(savedKey, savedJson);
    notifyListeners();
    return saved;
  }

  Future<void> setSavedFromRemote(
    Iterable<String> listingIds, {
    Map<String, CustomerActivityJson> snapshots =
        const <String, CustomerActivityJson>{},
  }) async {
    final Set<String> remoteIds = listingIds
        .where((String id) => id.trim().isNotEmpty)
        .toSet();
    final Map<String, CustomerActivityJson> existing =
        <String, CustomerActivityJson>{
          for (final CustomerActivityJson item in _saved)
            _listingId(item): item,
        };
    _saved
      ..clear()
      ..addAll(
        remoteIds.map(
          (String id) => _normalizeListing(
            snapshots[id] ?? existing[id] ?? <String, dynamic>{'id': id},
          ),
        ),
      );
    await _persist(_savedKey, _saved);
    notifyListeners();
  }

  Future<void> recordRecent(CustomerActivityJson listing) async {
    final CustomerActivityJson snapshot = _normalizeListing(listing);
    final String listingId = _listingId(snapshot);
    if (listingId.isEmpty) {
      return;
    }
    _recent.removeWhere(
      (CustomerActivityJson item) => _listingId(item) == listingId,
    );
    _recent.insert(0, snapshot);
    if (_recent.length > _maximumRecentItems) {
      _recent.removeRange(_maximumRecentItems, _recent.length);
    }
    await _persist(_recentKey, _recent);
    notifyListeners();
  }

  Future<void> clearRecentlyViewed() async {
    _recent.clear();
    await _persist(_recentKey, _recent);
    notifyListeners();
  }

  CustomerActivityJson? snapshotFor(String listingId) {
    for (final CustomerActivityJson item in <CustomerActivityJson>[
      ..._saved,
      ..._recent,
    ]) {
      if (_listingId(item) == listingId) {
        return item;
      }
    }
    return null;
  }

  Future<void> _persist(
    String key,
    List<CustomerActivityJson> snapshots,
  ) async {
    final SharedPreferences? preferences = _preferences;
    if (preferences == null) {
      return;
    }
    await preferences.setString(key, jsonEncode(snapshots));
  }

  List<CustomerActivityJson> _decodeSnapshots(String? encoded) {
    if (encoded == null || encoded.isEmpty) {
      return <CustomerActivityJson>[];
    }
    try {
      final List<dynamic> values = jsonDecode(encoded) as List<dynamic>;
      return values
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> item) => _normalizeListing(
              item.map(
                (dynamic key, dynamic value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              ),
            ),
          )
          .where((CustomerActivityJson item) => _listingId(item).isNotEmpty)
          .toList();
    } catch (_) {
      return <CustomerActivityJson>[];
    }
  }

  CustomerActivityJson _normalizeListing(CustomerActivityJson listing) {
    final String id = _listingId(listing);
    final Map<String, dynamic>? category =
        listing['asset_categories'] as Map<String, dynamic>?;
    return <String, dynamic>{
      'id': id,
      'listing_id': id,
      'title': listing['title']?.toString() ?? '',
      'public_location_label':
          listing['public_location_label']?.toString() ?? '',
      'price_amount': listing['price_amount'],
      'price_period': listing['price_period']?.toString(),
      'category_name':
          listing['category_name']?.toString() ?? category?['name']?.toString(),
      'cover_url': listing['cover_url']?.toString(),
      'cover_storage_path': listing['cover_storage_path']?.toString(),
      'viewed_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String _listingId(CustomerActivityJson listing) =>
      (listing['listing_id'] ?? listing['id'] ?? '').toString();
}
