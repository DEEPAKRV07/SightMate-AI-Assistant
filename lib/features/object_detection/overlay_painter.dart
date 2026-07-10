// lib/features/object_detection/overlay_painter.dart
// Detection overlay: draws bounding boxes scaled from normalized [0,1] to screen

import 'package:flutter/material.dart';
import 'yolo_service.dart';
import 'h_splitter.dart';

class OverlayPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final double frameWidth;
  final double frameHeight;
  final Offset? vanishingPoint;

  const OverlayPainter({
    required this.detections,
    required this.frameWidth,
    required this.frameHeight,
    this.vanishingPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Re-classify zones for coloring
    final zoned = HSplitter.classify(
      detections:  detections,
      frameWidth:  frameWidth,
      frameHeight: frameHeight,
      vanishingPoint: vanishingPoint,
    );

    for (final zd in zoned) {
      _drawBox(canvas, size, zd);
    }
  }

  void _drawBox(Canvas canvas, Size size, ZonedDetection zd) {
    final det  = zd.detection;
    final rect = det.rect; // Normalized [0,1]

    // Scale to screen pixels
    final screenRect = Rect.fromLTRB(
      rect.left   * size.width,
      rect.top    * size.height,
      rect.right  * size.width,
      rect.bottom * size.height,
    );

    // Zone-based color coding
    final color = _zoneColor(zd.zone, zd.shouldAlert);

    final boxPaint = Paint()
      ..color       = color
      ..style       = PaintingStyle.stroke
      ..strokeWidth = zd.shouldAlert ? 2.5 : 1.5;

    canvas.drawRect(screenRect, boxPaint);

    // Label background
    final label = '${det.label} ${(det.confidence * 100).toStringAsFixed(0)}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: zd.shouldAlert ? FontWeight.bold : FontWeight.normal,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: screenRect.width);

    final bgRect = Rect.fromLTWH(
      screenRect.left,
      screenRect.top - 16,
      textPainter.width + 4,
      16,
    );

    canvas.drawRect(bgRect, Paint()..color = color.withOpacity(0.7));
    textPainter.paint(canvas, Offset(screenRect.left + 2, screenRect.top - 15));
  }

  Color _zoneColor(SpatialZone zone, bool alert) {
    if (!alert) return Colors.white38;
    switch (zone) {
      case SpatialZone.centralPath: return Colors.redAccent;
      case SpatialZone.leftFlank:   return Colors.orangeAccent;
      case SpatialZone.rightFlank:  return Colors.orangeAccent;
      case SpatialZone.irrelevant:  return Colors.white30;
    }
  }

  @override
  bool shouldRepaint(covariant OverlayPainter old) =>
      old.detections != detections;
}
