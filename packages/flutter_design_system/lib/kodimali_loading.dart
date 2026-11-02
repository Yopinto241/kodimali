import 'package:flutter/material.dart';

/// A small, interruptible brand animation. Disposal stops it immediately.
class KodimaliLoading extends StatefulWidget {
  const KodimaliLoading({super.key, this.label = 'KODIMALI', this.size = 64});
  final String label;
  final double size;

  @override
  State<KodimaliLoading> createState() => _KodimaliLoadingState();
}

class _KodimaliLoadingState extends State<KodimaliLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _icon(Color color) => Image.asset(
    'packages/flutter_design_system/assets/kodimali-icon.png',
    width: widget.size,
    height: widget.size,
    color: color,
    excludeFromSemantics: true,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    liveRegion: true,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                children: [
                  _icon(Theme.of(context).colorScheme.outlineVariant),
                  ClipRect(
                    clipper: _FillClipper(_controller.value),
                    child: _icon(const Color(0xff147d69)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _FillClipper extends CustomClipper<Rect> {
  const _FillClipper(this.progress);
  final double progress;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, size.height * (1 - progress), size.width, size.height);
  @override
  bool shouldReclip(_FillClipper oldClipper) => progress != oldClipper.progress;
}
