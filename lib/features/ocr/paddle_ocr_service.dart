// lib/features/ocr/paddle_ocr_service.dart
// MODULE 2 – On-Device Screen Reader Mode via PaddleOCR (ONNX Runtime)
//
// Architecture:
//   • Detection: ch_PP-OCRv4_det_infer.onnx (DBNet text region detector)
//     - Input:  [1, 3, H, W] normalized RGB — dynamic H/W padded to 32x multiple
//     - Output: [1, 1, H/4, W/4] probability map
//   • Recognition: ch_PP-OCRv4_rec_infer.onnx (CRNN sequence recognizer)
//     - Input:  [1, 3, 48, W] — fixed 48px height, dynamic width
//     - Output: [1, T, numChars] CTC logits
//
// Execution pipeline:
//   1. Detect text region bounding boxes via DBNet
//   2. Crop each region from original image (with margin)
//   3. Feed crops sequentially into CRNN recognizer
//   4. CTC-greedy decode → clean text string
//
// NOTE: This service uses platform channels to invoke native ONNX Runtime
// sessions configured with NNAPI execution provider on Android.
// The Dart side calls into the native service via 'sightmate/paddle_ocr'.
//
// If ONNX models are not yet bundled, the service degrades to
// google_mlkit_text_recognition as a fallback.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class OcrRegion {
  final List<List<double>> polygon; // [[x0,y0],[x1,y1],[x2,y2],[x3,y3]]
  final String text;
  final double confidence;

  const OcrRegion({
    required this.polygon,
    required this.text,
    required this.confidence,
  });
}

class PaddleOCRResult {
  final String fullText;
  final List<OcrRegion> regions;
  final Duration inferenceTime;

  const PaddleOCRResult({
    required this.fullText,
    required this.regions,
    required this.inferenceTime,
  });
}

class PaddleOCRService {
  // Singleton
  static final PaddleOCRService _instance = PaddleOCRService._internal();
  factory PaddleOCRService() => _instance;
  PaddleOCRService._internal();

  static const MethodChannel _channel = MethodChannel('sightmate/paddle_ocr');

  bool _initialized = false;
  bool _busy        = false;

  // ── Initialize ONNX sessions (native side) ─────────────────────────────────
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      final success = await _channel.invokeMethod<bool>('initialize', {
        'detModelAsset': 'assets/models/ch_PP-OCRv4_det_infer.onnx',
        'recModelAsset': 'assets/models/ch_PP-OCRv4_rec_infer.onnx',
        'useNNAPI':      true,
        'numThreads':    4,
      });
      _initialized = success == true;
      return _initialized;
    } on PlatformException catch (e) {
      // Native OCR not yet available — will use MLKit fallback
      _initialized = false;
      return false;
    }
  }

  // ── Process image bytes → structured OCR result ────────────────────────────
  Future<PaddleOCRResult?> processImageBytes(Uint8List jpegBytes) async {
    if (_busy) return null;
    _busy = true;

    final stopwatch = Stopwatch()..start();

    try {
      if (!_initialized) {
        // Try to initialize on first call
        await initialize();
      }

      if (_initialized) {
        return await _runNativeOCR(jpegBytes, stopwatch);
      } else {
        // Native not available — use platform channel MLKit as backup
        return await _runMLKitFallback(jpegBytes, stopwatch);
      }
    } catch (e) {
      return null;
    } finally {
      _busy = false;
    }
  }

  // ── Native PaddleOCR path ─────────────────────────────────────────────────
  Future<PaddleOCRResult> _runNativeOCR(
    Uint8List jpegBytes,
    Stopwatch stopwatch,
  ) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'recognize',
      {'imageBytes': jpegBytes},
    );

    stopwatch.stop();

    if (result == null) {
      return PaddleOCRResult(
        fullText:      '',
        regions:       [],
        inferenceTime: stopwatch.elapsed,
      );
    }

    final rawRegions = result['regions'] as List<dynamic>? ?? [];
    final regions = rawRegions.map((r) {
      final polyRaw = (r['polygon'] as List<dynamic>)
          .map((pt) => (pt as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList();

      return OcrRegion(
        polygon:    polyRaw,
        text:       r['text'] as String? ?? '',
        confidence: (r['confidence'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    final fullText = regions
        .map((r) => r.text)
        .where((t) => t.isNotEmpty)
        .join(' ');

    return PaddleOCRResult(
      fullText:      fullText,
      regions:       regions,
      inferenceTime: stopwatch.elapsed,
    );
  }

  // ── MLKit fallback path (when ONNX models not bundled) ────────────────────
  Future<PaddleOCRResult> _runMLKitFallback(
    Uint8List jpegBytes,
    Stopwatch stopwatch,
  ) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'recognizeFallback',
        {'imageBytes': jpegBytes},
      );
      stopwatch.stop();
      return PaddleOCRResult(
        fullText:      result ?? '',
        regions:       [],
        inferenceTime: stopwatch.elapsed,
      );
    } catch (_) {
      stopwatch.stop();
      return PaddleOCRResult(
        fullText:      '',
        regions:       [],
        inferenceTime: stopwatch.elapsed,
      );
    }
  }

  void dispose() {
    _channel.invokeMethod('dispose').catchError((_) {});
    _initialized = false;
  }
}
