// lib/features/object_detection/motion_echo_filter.dart
// MODULE 1 – Motion Echo Filter (Ego-Motion Compensation)
//
// Dart-side interface for the native OpenCV optical flow pipeline.
// The actual Farneback / Lucas-Kanade computation runs in C++ native code
// via the 'sightmate/optical_flow' MethodChannel.
//
// Responsibilities:
//   • Send consecutive frame pairs to native for optical flow computation
//   • Receive affine ego-motion matrix (camera shake/sway)
//   • Apply ego-motion correction to bounding boxes from YOLO
//   • Flag detections as "genuinely moving" vs "static background shift"
//
// The C++ implementation (android/app/src/main/cpp/optical_flow_wrapper.cpp)
// performs:
//   1. Sparse Lucas-Kanade tracking on Shi-Tomasi corners
//   2. Affine transform estimation via estimateAffinePartial2D
//   3. Returns [dx, dy, rotation_rad, scale] as ego-motion parameters

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'yolo_service.dart';

class EgoMotionResult {
  final double dx;       // pixels horizontal shift
  final double dy;       // pixels vertical shift
  final double rotation; // radians
  final double scale;
  final double vpX;      // normalized vanishing point X (0.0 to 1.0)
  final double vpY;      // normalized vanishing point Y (0.0 to 1.0)
  final bool isReliable; // false if insufficient tracked points

  const EgoMotionResult({
    required this.dx,
    required this.dy,
    required this.rotation,
    required this.scale,
    required this.vpX,
    required this.vpY,
    required this.isReliable,
  });

  static const EgoMotionResult zero = EgoMotionResult(
    dx: 0, dy: 0, rotation: 0, scale: 1.0, vpX: 0.5, vpY: 0.42, isReliable: false,
  );
}

class FilteredDetection {
  final DetectionResult detection;
  final bool isGenuinelyMoving; // true = real hazard, false = background drift
  final double motionMagnitude; // pixels/frame of independent motion

  const FilteredDetection({
    required this.detection,
    required this.isGenuinelyMoving,
    required this.motionMagnitude,
  });
}

class MotionEchoFilter {
  // Singleton
  static final MotionEchoFilter _instance = MotionEchoFilter._internal();
  factory MotionEchoFilter() => _instance;
  MotionEchoFilter._internal();

  static const MethodChannel _channel = MethodChannel('sightmate/optical_flow');

  // Threshold: if a detection moves MORE than ego-motion by this factor,
  // it is classified as genuinely moving.
  static const double _independentMotionThreshold = 1.8;

  // ── Compute ego-motion from consecutive YUV frames ─────────────────────────
  //
  // [prevFrame] and [currFrame] are raw YUV_420_888 plane 0 (Y channel) bytes.
  // [width] and [height] are the Y plane dimensions.
  Future<EgoMotionResult> computeEgoMotion({
    required Uint8List prevFrame,
    required Uint8List currFrame,
    required int width,
    required int height,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'computeOpticalFlow',
        {
          'prevY': prevFrame,
          'currY': currFrame,
          'width': width,
          'height': height,
        },
      );

      if (result == null) return EgoMotionResult.zero;

      return EgoMotionResult(
        dx:        (result['dx']       as num?)?.toDouble() ?? 0.0,
        dy:        (result['dy']       as num?)?.toDouble() ?? 0.0,
        rotation:  (result['rotation'] as num?)?.toDouble() ?? 0.0,
        scale:     (result['scale']    as num?)?.toDouble() ?? 1.0,
        vpX:       (result['vp_x']     as num?)?.toDouble() ?? 0.5,
        vpY:       (result['vp_y']     as num?)?.toDouble() ?? 0.42,
        isReliable: (result['reliable'] as bool?) ?? false,
      );
    } on PlatformException catch (e) {
      // Native not yet linked (debug builds without NDK) — degrade gracefully
      return EgoMotionResult.zero;
    }
  }

  // ── Apply ego-motion compensation to detections ────────────────────────────
  //
  // For each detected bounding box, compare the box's observed motion
  // (from the previous frame) against the ego-motion. If independent
  // motion is significant, flag as genuinely moving hazard.
  //
  // [prevDetections] = detections from t-1 frame (for motion tracking)
  // [currDetections] = detections from current frame
  // [egoMotion]      = estimated camera movement
  List<FilteredDetection> applyFilter({
    required List<DetectionResult> prevDetections,
    required List<DetectionResult> currDetections,
    required EgoMotionResult egoMotion,
  }) {
    final egoMag = (egoMotion.isReliable)
        ? (egoMotion.dx.abs() + egoMotion.dy.abs())
        : 0.0;

    return currDetections.map((curr) {
      // Try to match with a detection from the previous frame by label
      final prev = prevDetections
          .where((p) => p.label == curr.label)
          .fold<DetectionResult?>(null, (best, candidate) {
        if (best == null) return candidate;
        final bestDist = _centerDist(best.rect, curr.rect);
        final candDist = _centerDist(candidate.rect, curr.rect);
        return candDist < bestDist ? candidate : best;
      });

      if (prev == null) {
        // New detection — cannot determine motion, treat as static
        return FilteredDetection(
          detection: curr,
          isGenuinelyMoving: false,
          motionMagnitude: 0.0,
        );
      }

      // Observed motion of the bounding box center
      final observedDx = _cx(curr.rect) - _cx(prev.rect);
      final observedDy = _cy(curr.rect) - _cy(prev.rect);
      final observedMag = observedDx.abs() + observedDy.abs();

      // Independent motion = observed motion − ego motion
      final independentMag = (observedMag - egoMag).clamp(0.0, double.infinity);

      final isMoving = egoMotion.isReliable
          ? (independentMag > egoMag * _independentMotionThreshold)
          : (observedMag > 5.0); // fallback: any significant box movement

      return FilteredDetection(
        detection: curr,
        isGenuinelyMoving: isMoving,
        motionMagnitude: independentMag,
      );
    }).toList();
  }

  double _centerDist(Rect a, Rect b) {
    final dx = _cx(a) - _cx(b);
    final dy = _cy(a) - _cy(b);
    return (dx * dx + dy * dy);
  }

  double _cx(Rect r) => r.left + r.width  / 2;
  double _cy(Rect r) => r.top  + r.height / 2;
}
