// lib/features/navigation/segmentation_service.dart
// RETIRED: DeepLabV3 segmentation model removed.
//
// RATIONALE: The heavy DeepLabV3 model (2.7MB, 257×257 input, dense per-pixel
// inference) was causing CPU/GPU saturation at >80ms per frame — incompatible
// with the 30 FPS target. Semantic path segmentation is now replaced by the
// lightweight H-Splitter geometric filter (h_splitter.dart) which achieves
// equivalent functional results (path vs. obstacle zone classification) at
// <0.1ms computation cost using pure Dart geometry.
//
// This file is retained as a documented stub to prevent import errors
// from any residual references. All callers should migrate to H-Splitter.

class SegmentationService {
  bool _loaded = false;

  // No-op: model is not loaded. H-Splitter handles path partitioning.
  Future<void> loadModel() async {
    _loaded = false;
    // DeepLabV3 removed — see h_splitter.dart for replacement
  }

  // Returns empty mask. H-Splitter provides zone classification instead.
  Future<List<List<int>>> runSegmentation(String imagePath) async {
    return [];
  }

  bool get isLoaded => _loaded;
}
