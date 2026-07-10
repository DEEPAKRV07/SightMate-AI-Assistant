// lib/features/object_detection/h_splitter.dart
// MODULE 1 – H-Splitter / H-Box Spatial Filter
//
// Geometric path partitioning into three spatial zones:
//   • Area 3 (Central Path): trapezoidal region mapping the user's walking path
//   • Area 1 (Left Flank): left peripheral zone
//   • Area 2 (Right Flank): right peripheral zone
//
// Filtering logic:
//   • Always report objects in Area 3 (central path)
//   • Report peripheral objects only if they occupy >12% of total frame area
//
// Vanishing point estimation uses a simplified geometric approach:
//   horizontal midpoint, at 45% frame height — suitable for mobile cameras
//   held at chest/neck level for walking blind users.

import 'package:flutter/material.dart';
import 'yolo_service.dart';

// ─── Zone classification ─────────────────────────────────────────────────────

enum SpatialZone { centralPath, leftFlank, rightFlank, irrelevant }

class ZonedDetection {
  final DetectionResult detection;
  final SpatialZone zone;
  final double frameOccupancyRatio; // fraction of total frame area

  const ZonedDetection({
    required this.detection,
    required this.zone,
    required this.frameOccupancyRatio,
  });

  /// Returns true if this detection should trigger a TTS alert.
  bool get shouldAlert {
    switch (zone) {
      case SpatialZone.centralPath:
        return true; // Always alert for central path objects
      case SpatialZone.leftFlank:
      case SpatialZone.rightFlank:
        return frameOccupancyRatio > 0.12; // >12% frame area threshold
      case SpatialZone.irrelevant:
        return false;
    }
  }

  String get zoneLabel {
    switch (zone) {
      case SpatialZone.centralPath:  return 'front';
      case SpatialZone.leftFlank:    return 'left';
      case SpatialZone.rightFlank:   return 'right';
      case SpatialZone.irrelevant:   return '';
    }
  }
}

// ─── HSplitter ───────────────────────────────────────────────────────────────

class HSplitter {
  // Default static vanishing point as fraction of frame dimensions.
  // vp.dx = 0.5 (center), vp.dy = 0.42 (slightly above midframe).
  static const Offset defaultVanishingPoint = Offset(0.5, 0.42);

  // Constants defining trapezoid size and position relative to vanishing point
  static const double _topHalfWidth = 0.10; // width of top edge is 20% of frame width
  static const double _offsetY       = 0.15; // top edge is 15% frame height below vanishing point

  /// Classify all raw detections into spatial zones relative to a dynamic vanishing point.
  /// [frameWidth] and [frameHeight] are the pixel dimensions of the camera frame.
  /// [vanishingPoint] is the normalized coordinate (0.0 to 1.0) of the motion center.
  static List<ZonedDetection> classify({
    required List<DetectionResult> detections,
    required double frameWidth,
    required double frameHeight,
    Offset? vanishingPoint,
  }) {
    final vp = vanishingPoint ?? defaultVanishingPoint;
    final totalArea = frameWidth * frameHeight;
    final results = <ZonedDetection>[];

    // Compute dynamic trapezoid boundaries based on current vanishing point
    final poly = _getTrapezoid(vp);

    for (final det in detections) {
      final rect = det.rect;

      // Center-of-mass of bounding box as frame fractions
      final cx = (rect.left + rect.width  / 2) / frameWidth;
      final cy = (rect.top  + rect.height / 2) / frameHeight;

      // Occupancy ratio
      final boxArea = rect.width * rect.height;
      final occupancy = boxArea / totalArea;

      // If object center is above the horizon line (vp.dy + offsetY), it's irrelevant
      SpatialZone zone;
      if (cy <= vp.dy + _offsetY) {
        zone = SpatialZone.irrelevant;
      } else if (_isInsidePolygon(cx, cy, poly)) {
        zone = SpatialZone.centralPath;
      } else if (cx < vp.dx) {
        zone = SpatialZone.leftFlank;
      } else {
        zone = SpatialZone.rightFlank;
      }

      results.add(ZonedDetection(
        detection: det,
        zone: zone,
        frameOccupancyRatio: occupancy,
      ));
    }

    return results;
  }

  /// Returns only detections that pass the alerting threshold.
  static List<ZonedDetection> alertingDetections({
    required List<DetectionResult> detections,
    required double frameWidth,
    required double frameHeight,
    Offset? vanishingPoint,
  }) {
    return classify(
      detections: detections,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      vanishingPoint: vanishingPoint,
    ).where((zd) => zd.shouldAlert).toList();
  }

  // ── Helper: Compute dynamic trapezoid corners ──────────────────────────────

  static List<Offset> _getTrapezoid(Offset vp) {
    return [
      Offset((vp.dx - _topHalfWidth).clamp(0.0, 1.0), (vp.dy + _offsetY).clamp(0.0, 1.0)), // top-left
      Offset((vp.dx + _topHalfWidth).clamp(0.0, 1.0), (vp.dy + _offsetY).clamp(0.0, 1.0)), // top-right
      const Offset(0.95, 1.00), // bottom-right
      const Offset(0.05, 1.00), // bottom-left
    ];
  }

  /// Point-in-polygon test for the trapezoidal central zone (winding number).
  static bool _isInsidePolygon(double px, double py, List<Offset> poly) {
    int n = poly.length;
    int windingNumber = 0;

    for (int i = 0; i < n; i++) {
      final p1 = poly[i];
      final p2 = poly[(i + 1) % n];

      if (p1.dy <= py) {
        if (p2.dy > py) {
          // Upward crossing
          if (_isLeft(p1, p2, px, py) > 0) windingNumber++;
        }
      } else {
        if (p2.dy <= py) {
          // Downward crossing
          if (_isLeft(p1, p2, px, py) < 0) windingNumber--;
        }
      }
    }

    return windingNumber != 0;
  }

  static double _isLeft(Offset p1, Offset p2, double px, double py) {
    return (p2.dx - p1.dx) * (py - p1.dy) - (px - p1.dx) * (p2.dy - p1.dy);
  }

  // ── Trapezoid overlay path for debug visualization ─────────────────────────

  /// Returns the trapezoid as screen pixel coordinates for CustomPainter.
  static Path trapezoidPath(double frameWidth, double frameHeight, Offset? vanishingPoint) {
    final vp = vanishingPoint ?? defaultVanishingPoint;
    final path = Path();
    final poly = _getTrapezoid(vp);
    final corners = poly.map((f) =>
      Offset(f.dx * frameWidth, f.dy * frameHeight)).toList();

    path.moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < corners.length; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();
    return path;
  }
}
