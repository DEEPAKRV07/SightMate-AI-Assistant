// lib/features/navigation/navigation_fusion_service.dart
// Navigation Fusion Service
//
// Originally fused YOLO detections + segmentation mask for path guidance.
// Now fuses YOLO detections + H-Splitter zones for directional TTS narration.
// Segmentation dependency removed.

import '../object_detection/h_splitter.dart';
import '../object_detection/yolo_service.dart';

class PathGuidance {
  final String instruction;
  final bool   isUrgent;
  const PathGuidance(this.instruction, {this.isUrgent = false});
}

class NavigationFusionService {
  // Singleton
  static final NavigationFusionService _instance =
      NavigationFusionService._internal();
  factory NavigationFusionService() => _instance;
  NavigationFusionService._internal();

  /// Generate a concise navigation instruction from zoned detections.
  PathGuidance? generateInstruction({
    required List<ZonedDetection> zoned,
    required double frameWidth,
    required double frameHeight,
  }) {
    final alerting = zoned.where((z) => z.shouldAlert).toList();
    if (alerting.isEmpty) return null;

    // Check if central path is blocked
    final centralBlocked = alerting.any((z) => z.zone == SpatialZone.centralPath);
    final leftBlocked    = alerting.any((z) => z.zone == SpatialZone.leftFlank);
    final rightBlocked   = alerting.any((z) => z.zone == SpatialZone.rightFlank);

    if (centralBlocked && !leftBlocked) {
      return PathGuidance('Obstacle ahead, move left.', isUrgent: true);
    } else if (centralBlocked && !rightBlocked) {
      return PathGuidance('Obstacle ahead, move right.', isUrgent: true);
    } else if (centralBlocked) {
      return PathGuidance('Obstacle immediate front, stop.', isUrgent: true);
    } else if (leftBlocked && !rightBlocked) {
      return PathGuidance('Obstacle on left.', isUrgent: false);
    } else if (rightBlocked && !leftBlocked) {
      return PathGuidance('Obstacle on right.', isUrgent: false);
    }

    return null;
  }
}
