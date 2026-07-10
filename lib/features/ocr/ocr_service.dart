// lib/features/ocr/ocr_service.dart
// MODULE 2 – OCR Service (façade over PaddleOCRService + legacy fallback)
//
// Migration strategy:
//   • Primary: PaddleOCR via ONNX Runtime (when ONNX models bundled)
//   • Fallback: google_mlkit_text_recognition (current implementation)
// The existing ocr_page.dart continues to call OCRService.processImage()
// with no API changes required.

import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'paddle_ocr_service.dart';

class OCRService {
  // Singleton
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final _paddleOCR   = PaddleOCRService();
  final _mlkitOCR    = TextRecognizer(script: TextRecognitionScript.latin);

  bool _isProcessing = false;
  String _lastSpokenText = '';
  DateTime _lastSpokenTime = DateTime.now();

  static const int throttleMs = 1500;
  static const int cooldownMs = 4000;

  // ── Primary API — accepts file path (existing callers) ─────────────────────
  Future<String?> processImageFromPath(String imagePath) async {
    if (_isProcessing) return null;

    final now = DateTime.now();
    if (now.difference(_lastSpokenTime).inMilliseconds < cooldownMs) return null;

    _isProcessing = true;

    try {
      // Read file bytes
      final bytes = await File(imagePath).readAsBytes();
      return await _processBytes(bytes);
    } finally {
      _isProcessing = false;
    }
  }

  // ── Accept InputImage (compatibility with ocr_page.dart) ──────────────────
  Future<String?> processImage(InputImage inputImage) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      // Try PaddleOCR first
      if (inputImage.filePath != null) {
        final bytes = await File(inputImage.filePath!).readAsBytes();
        final result = await _paddleOCR.processImageBytes(bytes);
        if (result != null && result.fullText.isNotEmpty) {
          return _applyDedup(result.fullText);
        }
      }

      // Fallback to MLKit
      final recognized = await _mlkitOCR.processImage(inputImage);
      final cleaned = _cleanText(recognized.text);
      return cleaned.isEmpty ? null : _applyDedup(cleaned);
    } finally {
      _isProcessing = false;
    }
  }

  // ── Internal processing ───────────────────────────────────────────────────
  Future<String?> _processBytes(Uint8List bytes) async {
    // Try PaddleOCR
    final result = await _paddleOCR.processImageBytes(bytes);
    if (result != null && result.fullText.isNotEmpty) {
      return _applyDedup(result.fullText);
    }

    // Fallback to MLKit via temp file
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(bytes);

    try {
      final inputImage = InputImage.fromFile(tempFile);
      final recognized = await _mlkitOCR.processImage(inputImage);
      final cleaned = _cleanText(recognized.text);
      return cleaned.isEmpty ? null : _applyDedup(cleaned);
    } finally {
      await tempFile.delete().catchError((_) {});
    }
  }

  String? _applyDedup(String text) {
    final cleaned = _cleanText(text);
    if (cleaned.isEmpty) return null;
    if (cleaned == _lastSpokenText) return null;
    _lastSpokenText = cleaned;
    _lastSpokenTime = DateTime.now();
    return cleaned;
  }

  String _cleanText(String raw) {
    return raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '')
        .trim();
  }

  void dispose() {
    _mlkitOCR.close();
    _paddleOCR.dispose();
  }
}