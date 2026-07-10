// lib/features/navigation/segmentation_overlay.dart
// RETIRED: Segmentation overlay removed with DeepLabV3.
// Retained as no-op to prevent import errors.

import 'package:flutter/material.dart';

class SegmentationOverlay extends StatelessWidget {
  const SegmentationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // No-op — H-Splitter trapezoid overlay in ObjectDetectionPage replaces this
    return const SizedBox.shrink();
  }
}
