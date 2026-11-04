import 'dart:convert';

Map<String, dynamic> decodePushTap(String payload) {
  try {
    final value = jsonDecode(payload);
    if (value is Map) return Map<String, dynamic>.from(value);
  } catch (_) {}
  return {'route': payload}; // Compatible with earlier local notifications.
}

bool pushBelongsToUser(Map<String, dynamic> payload, String? user) =>
    user != null && (payload['userId'] == null || payload['userId'] == user);
