import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef LodgeRow = Map<String, dynamic>;

/// All clients use the same tenant-scoped database operations. Injectable for
/// navigation/UI tests; no staff privileges are inferred from marketplace roles.
class LodgeApi {
  LodgeApi(this.client);
  final SupabaseClient client;
  Future<LodgeRow> workspace({
    String? lodgeId,
    String section = 'dashboard',
    String? start,
    String? end,
    int offset = 0,
    int limit = 30,
    String query = '',
    String roomType = '',
  }) async => Map<String, dynamic>.from(
    await client.rpc(
          'lodge_workspace',
          params: {
            'p_lodge': lodgeId,
            'p_section': section,
            'p_start': start,
            'p_end': end,
            'p_offset': offset,
            'p_limit': limit,
            'p_query': query,
            'p_room_type': roomType,
          },
        )
        as Map,
  );
  Future<dynamic> command(String lodgeId, String action, LodgeRow data) =>
      client.rpc(
        'lodge_command',
        params: {'p_lodge': lodgeId, 'p_action': action, 'p_data': data},
      );
  Future<String> register(LodgeRow data) async =>
      (await client.rpc('lodge_register', params: {'p_data': data})).toString();
  Future<dynamic> enquire(String lodgeId, LodgeRow data) =>
      client.rpc('lodge_enquire', params: {'p_lodge': lodgeId, 'p_data': data});
  Future<List<LodgeRow>> myRequests(String lodgeId) async =>
      (await client.rpc('lodge_my_requests', params: {'p_lodge': lodgeId})
              as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  Future<LodgeRow> discover({
    String? id,
    String search = '',
    String? locationId,
    String? arrival,
    String? departure,
    int offset = 0,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
          'public_lodges',
          params: {
            'p_id': id,
            'p_search': search,
            'p_location': locationId,
            'p_arrival': arrival,
            'p_departure': departure,
            'p_offset': offset,
            'p_limit': 20,
          },
        )
        as Map,
  );
  Future<List<LodgeRow>> locations(String text) async =>
      (await client.rpc(
                'suggest_marketplace_locations',
                params: {'p_query': text},
              )
              as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
  Future<Map<String, String>> images(List<String> paths) async {
    if (paths.isEmpty) return {};
    final signed = await client.storage
        .from('lodge-media')
        .createSignedUrlsResult(paths.toSet().toList(), 3600);
    return {
      for (final s in signed)
        if (s is SignedUrlSuccess) s.path: s.signedUrl,
    };
  }

  Future<String> uploadImage(String lodgeId, Uint8List bytes) async {
    final path =
        '$lodgeId/photos/${DateTime.now().microsecondsSinceEpoch}-${client.auth.currentUser!.id}.jpg';
    await client.storage
        .from('lodge-media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '86400',
            upsert: false,
          ),
        );
    return path;
  }
}
