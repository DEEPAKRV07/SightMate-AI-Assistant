import 'package:flutter/material.dart';

class SegmentationOverlay extends CustomPainter {
  final List<List<int>> mask;

  SegmentationOverlay(this.mask);

  @override
  void paint(Canvas canvas, Size size) {
    if (mask.isEmpty) return;

    int h = mask.length;
    int w = mask[0].length;

    int step = 6;

    double cellW = size.width / w;
    double cellH = size.height / h;

    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        int label = mask[y][x];

        Color color;

        /// floor / walkable
        if (label == 0) {
          color = Colors.green.withOpacity(0.12);
        }

        /// person
        else if (label == 15) {
          color = Colors.yellow.withOpacity(0.25);
        }

        /// TV / monitor
        else if (label == 20) {
          color = Colors.blue.withOpacity(0.25);
        }

        /// other obstacles
        else {
          color = Colors.red.withOpacity(0.20);
        }

        final paint = Paint()..color = color;

        Rect rect = Rect.fromLTWH(
          x * cellW,
          y * cellH,
          cellW * step,
          cellH * step,
        );

        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
