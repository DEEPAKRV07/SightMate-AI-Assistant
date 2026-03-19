import 'package:flutter/material.dart';
import 'yolo_service.dart';

class OverlayPainter extends CustomPainter {
  final List<DetectionResult> results;

  OverlayPainter(this.results);

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var r in results) {
      final left = r.rect.left * size.width;
      final top = r.rect.top * size.height;
      final right = r.rect.right * size.width;
      final bottom = r.rect.bottom * size.height;

      final rect = Rect.fromLTRB(left, top, right, bottom);

      canvas.drawRect(rect, boxPaint);

      final textSpan = TextSpan(
        text: "${r.label} ${(r.confidence * 100).toStringAsFixed(0)}%",
        style: const TextStyle(
          color: Colors.green,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      textPainter.text = textSpan;
      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(left, top - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
