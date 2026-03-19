// lib/features/ocr/ocr_service.dart

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:async';

class OCRService {
  final TextRecognizer _textRecognizer =
  TextRecognizer(script: TextRecognitionScript.latin);

  bool _isProcessing = false;

  String _lastSpokenText = "";
  DateTime _lastSpokenTime = DateTime.now();

  final int throttleMs = 1500;        // frame throttle
  final int cooldownMs = 4000;        // speech cooldown

  Future<String?> processImage(InputImage inputImage) async {
    if (_isProcessing) return null;

    _isProcessing = true;

    try {
      final RecognizedText recognizedText =
      await _textRecognizer.processImage(inputImage);

      final cleaned = _cleanText(recognizedText.text);

      if (cleaned.isEmpty) return null;

      // Ignore very short fragments
      if (cleaned.length < 6) return null;

      // Similarity filter
      if (_isSimilar(cleaned, _lastSpokenText)) return null;

      // Cooldown protection
      if (DateTime.now()
          .difference(_lastSpokenTime)
          .inMilliseconds <
          cooldownMs) {
        return null;
      }

      _lastSpokenText = cleaned;
      _lastSpokenTime = DateTime.now();

      return cleaned;

    } catch (e) {
      print("OCR ERROR: $e");
      return null;
    } finally {
      await Future.delayed(Duration(milliseconds: throttleMs));
      _isProcessing = false;
    }
  }

  String _cleanText(String raw) {
    String text = raw.trim();

    text = text.replaceAll("\n\n", "\n");

    return text;
  }

  bool _isSimilar(String current, String previous) {
    if (previous.isEmpty) return false;

    final shorter =
    current.length < previous.length ? current : previous;

    int matchCount = 0;

    for (int i = 0; i < shorter.length; i++) {
      if (current.contains(shorter[i])) {
        matchCount++;
      }
    }

    double similarity = matchCount / shorter.length;

    return similarity > 0.8;
  }

  void dispose() {
    _textRecognizer.close();
  }
}