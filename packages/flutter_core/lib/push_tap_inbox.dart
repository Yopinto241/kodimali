import 'dart:async';

/// Keeps a cold-start tap until the app's navigation listener is attached.
class PushTapInbox {
  PushTapInbox() {
    _controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () => scheduleMicrotask(_flush),
    );
  }
  late final StreamController<Map<String, dynamic>> _controller;
  final List<Map<String, dynamic>> _pending = [];
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void add(Map<String, dynamic> payload) {
    if (_controller.isClosed) return;
    if (!_controller.hasListener) {
      _pending.add(Map.of(payload));
      if (_pending.length > 10) _pending.removeAt(0);
    } else {
      _controller.add(Map.of(payload));
    }
  }

  void _flush() {
    if (!_controller.hasListener || _controller.isClosed) return;
    final pending = List<Map<String, dynamic>>.of(_pending);
    _pending.clear();
    for (final payload in pending) {
      _controller.add(payload);
    }
  }

  Future<void> close() => _controller.close();
}
