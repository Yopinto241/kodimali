import 'package:flutter/material.dart';

class WhatsAppIcon extends StatelessWidget {
  const WhatsAppIcon({super.key, this.color = Colors.white, this.size = 24});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _WhatsAppPainter(color));
}

class _WhatsAppPainter extends CustomPainter {
  _WhatsAppPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final bubble = Path()
      ..moveTo(20, 11.7)
      ..cubicTo(20, 18, 14, 22, 8.2, 18.7)
      ..lineTo(4, 20)
      ..lineTo(5.3, 15.9)
      ..cubicTo(1, 9, 6, 3, 12, 3)
      ..cubicTo(17, 3, 20, 7, 20, 11.7)
      ..close();
    canvas.drawPath(
      bubble,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    final phone = Path()
      ..moveTo(9, 7.8)
      ..cubicTo(8.4, 7.8, 8, 8.6, 8, 9.2)
      ..cubicTo(8, 11.7, 11.3, 15, 13.8, 15)
      ..cubicTo(14.5, 15, 15.3, 14.6, 15.3, 14)
      ..lineTo(13.3, 13)
      ..lineTo(12.3, 14)
      ..cubicTo(11.2, 13.5, 9.7, 12, 9.2, 10.9)
      ..lineTo(10.2, 9.9)
      ..close();
    canvas.drawPath(phone, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WhatsAppPainter oldDelegate) =>
      oldDelegate.color != color;
}
