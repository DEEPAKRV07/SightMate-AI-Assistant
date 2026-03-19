import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _isSpeaking = false;

  static Future<void> init() async {
    if (_initialized) return;

    await _tts.setSpeechRate(0.35); // steady speed
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _initialized = true;
  }

  static Future<void> speak(String text) async {
    await init();

    if (_isSpeaking) return;

    await _tts.stop(); // ensures clean start
    await _tts.speak(text);
  }

  static Future<void> stop() async {
    await init();
    await _tts.stop();
    _isSpeaking = false;
  }

  static bool get isSpeaking => _isSpeaking;
}