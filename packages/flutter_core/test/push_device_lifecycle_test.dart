import 'package:flutter_core/push_payload.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_core/push_device_lifecycle.dart';
import 'package:flutter_core/user_messages.dart';

void main() {
  test(
    'push payloads retain event identifiers and suppress a different account',
    () {
      final data = decodePushTap(
        '{"route":"account/events","eventPlanId":"fixture","userId":"A"}',
      );
      expect(data['eventPlanId'], 'fixture');
      expect(pushBelongsToUser(data, 'A'), isTrue);
      expect(pushBelongsToUser(data, 'B'), isFalse);
      expect(pushBelongsToUser(data, null), isFalse);
      expect(decodePushTap('chat/legacy')['route'], 'chat/legacy');
    },
  );

  test(
    'offline logout persists disable capability; A never registers as B',
    () async {
      String? user = 'A';
      List<DeviceRecord> stored = [];
      final enabled = <String, String>{};
      bool offline = false;
      final lifecycle = PushDeviceLifecycle(
        currentUser: () => user,
        read: () async => stored.map((r) => Map<String, String>.of(r)).toList(),
        write: (rows) async {
          stored = rows.map((r) => Map<String, String>.of(r)).toList();
        },
        register: (row) async {
          enabled[row['token']!] = row['user']!;
        },
        unregister: (row) async {
          if (offline) throw StateError('offline');
          enabled.remove(row['token']);
        },
      );
      await lifecycle.synchronize('token');
      expect(enabled['token'], 'A');
      offline = true;
      await lifecycle.disable();
      user = null;
      expect(stored.single['pending'], 'true');
      offline = false;
      await lifecycle.flush();
      expect(enabled, isEmpty);
      user = 'B';
      await lifecycle.synchronize('token');
      expect(enabled['token'], 'B');
      expect(stored.single['user'], 'B');
    },
  );
  test(
    'in-flight registration is disabled when logout races its completion',
    () async {
      String? user = 'A';
      List<DeviceRecord> records = [];
      final started = Completer<void>(), finish = Completer<void>();
      bool disabled = false;
      final lifecycle = PushDeviceLifecycle(
        currentUser: () => user,
        read: () async => records,
        write: (rows) async {
          records = rows;
        },
        register: (row) async {
          started.complete();
          await finish.future;
        },
        unregister: (row) async {
          disabled = true;
        },
      );
      final registering = lifecycle.synchronize('token');
      await started.future;
      user = null;
      final logout = lifecycle.disable();
      finish.complete();
      await registering;
      await logout;
      expect(disabled, isTrue);
      expect(records, isEmpty);
    },
  );
  test('technical diagnostics never appear in safe bilingual errors', () {
    for (final language in ['en', 'sw']) {
      for (final raw in [
        'permission denied for secret_table; token=secret',
        'SELECT * FROM private_table',
        r'C:\secret\key.json',
      ]) {
        final message = safeUserMessage(StateError(raw), language: language);
        expect(message, isNot(contains('secret')));
        expect(message, isNot(contains('SELECT')));
        expect(message, isNot(contains('private_table')));
      }
    }
  });
}
