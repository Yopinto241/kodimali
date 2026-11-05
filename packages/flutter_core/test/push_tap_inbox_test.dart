import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_core/push_tap_inbox.dart';

void main() {
  test(
    'cold-start taps survive listener attachment and are consumed once',
    () async {
      final inbox = PushTapInbox();
      inbox.add({'route': 'listing/one'});
      final received = <Map<String, dynamic>>[];
      final subscription = inbox.stream.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received, [
        {'route': 'listing/one'},
      ]);
      await subscription.cancel();
      final second = inbox.stream.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      inbox.add({'route': 'chat/two'});
      await Future<void>.delayed(Duration.zero);
      expect(received.last['route'], 'chat/two');
      await second.cancel();
      await inbox.close();
    },
  );
}
