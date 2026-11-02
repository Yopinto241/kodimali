import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _session =
    'customer-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
void recordCustomerPromotion(String id, String event) {
  try {
    unawaited(
      Supabase.instance.client
          .rpc(
            'record_platform_promotion_event',
            params: {
              'p_promotion_id': id,
              'p_event_type': event,
              'p_surface': 'customer_app',
              'p_session_key': _session,
            },
          )
          .then<void>((_) {})
          .catchError((Object _) {}),
    );
  } catch (_) {
    /* Optional analytics. */
  }
}

class PromotionExposure extends StatefulWidget {
  const PromotionExposure({
    super.key,
    required this.promotionId,
    required this.child,
    this.onImpression,
    this.onVisibilityChanged,
    this.trackImpression = true,
  });
  final String promotionId;
  final Widget child;
  final VoidCallback? onImpression;
  final ValueChanged<bool>? onVisibilityChanged;
  final bool trackImpression;
  @override
  State<PromotionExposure> createState() => _PromotionExposureState();
}

class _PromotionExposureState extends State<PromotionExposure>
    with WidgetsBindingObserver {
  final Set<ScrollPosition> _positions = {};
  final List<ScrollableState> _scrollables = [];
  Timer? _timer;
  bool _seen = false;
  bool _resumed = true;
  bool? _lastVisible;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final position in _positions) {
      position.removeListener(_check);
    }
    _positions.clear();
    _scrollables.clear();
    // Depend on the nearest scrollable and listen to every enclosing axis:
    // a horizontal sponsored row also moves with the vertical listing feed.
    Scrollable.maybeOf(context);
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        _scrollables.add(scrollable);
        _positions.add(scrollable.position);
      }
      return true;
    });
    for (final position in _positions) {
      position.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  bool _visible() {
    if (!mounted ||
        !_resumed ||
        ModalRoute.of(context)?.isCurrent == false ||
        !TickerMode.valuesOf(context).enabled) {
      return false;
    }
    var offstage = false;
    context.visitAncestorElements((element) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage) {
        offstage = true;
      }
      return !offstage;
    });
    if (offstage) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    var visible = rect.intersect(screen);
    for (final scrollable in _scrollables) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is RenderBox && viewport.hasSize && viewport.attached) {
        visible = visible.intersect(
          viewport.localToGlobal(Offset.zero) & viewport.size,
        );
      }
    }
    return rect.width > 0 &&
        rect.height > 0 &&
        !visible.isEmpty &&
        visible.width * visible.height >= rect.width * rect.height * .5;
  }

  void _check() {
    final visible = _visible();
    if (visible != _lastVisible) {
      _lastVisible = visible;
      widget.onVisibilityChanged?.call(visible);
    }
    if (!widget.trackImpression) return;
    if (_seen) return;
    if (!visible) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(const Duration(seconds: 1), () {
      _timer = null;
      if (_visible() && !_seen) {
        _seen = true;
        if (widget.onImpression != null) {
          widget.onImpression!();
        } else {
          recordCustomerPromotion(widget.promotionId, 'impression');
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final position in _positions) {
      position.removeListener(_check);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
