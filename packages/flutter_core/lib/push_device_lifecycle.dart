import 'dart:async';
import 'dart:convert';
import 'dart:math';

typedef DeviceRecord = Map<String, String>;

/// Serializes installation registration and account changes. The durable
/// disable queue works after offline logout without saving an old session JWT.
class PushDeviceLifecycle {
  PushDeviceLifecycle({
    required this.read,
    required this.write,
    required this.register,
    required this.unregister,
    required this.currentUser,
  });
  final Future<List<DeviceRecord>> Function() read;
  final Future<void> Function(List<DeviceRecord>) write;
  final Future<void> Function(DeviceRecord) register;
  final Future<void> Function(DeviceRecord) unregister;
  final String? Function() currentUser;
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;

  Future<void> _serial(Future<void> Function() operation) {
    final task = _tail.catchError((Object _) {}).then((_) => operation());
    _tail = task;
    return task;
  }

  Future<void> disable() {
    _epoch++;
    return _serial(() async {
      final records = await read();
      for (final record in records) {
        record['pending'] = 'true';
      }
      await write(
        records,
      ); // Persist before network: offline logout is recoverable.
      await _flush(records);
    });
  }

  Future<void> synchronize(String token) {
    final user = currentUser();
    final epoch = _epoch;
    return _serial(() async {
      final records = await read();
      for (final record in records) {
        if (record['user'] != user || record['token'] != token)
          record['pending'] = 'true';
      }
      await write(records);
      await _flush(records);
      if (user == null || user != currentUser() || epoch != _epoch) return;
      final active = records
          .where(
            (r) =>
                r['pending'] != 'true' &&
                r['token'] == token &&
                r['user'] == user,
          )
          .firstOrNull;
      final record =
          active ??
          <String, String>{
            'user': user,
            'token': token,
            'capability': base64Url.encode(
              List.generate(32, (_) => Random.secure().nextInt(256)),
            ),
          };
      if (active == null) {
        records.add(record);
        await write(records);
      }
      await register(record).timeout(const Duration(seconds: 8));
      if (user != currentUser() || epoch != _epoch) {
        record['pending'] = 'true';
        await write(records);
        await _flush(records);
      }
    });
  }

  Future<void> flush() => _serial(() async {
    final records = await read();
    await _flush(records);
  });

  Future<void> _flush(List<DeviceRecord> records) async {
    for (final record in List<DeviceRecord>.of(records)) {
      if (record['pending'] != 'true') continue;
      try {
        await unregister(record).timeout(const Duration(seconds: 3));
        records.remove(record);
      } catch (_) {
        /* Durable capability remains queued for next startup/login. */
      }
    }
    await write(records);
  }
}
