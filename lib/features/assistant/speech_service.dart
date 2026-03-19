import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  Future<void> init() async {
    if (!_initialized) {
      _initialized = await _speech.initialize();
      print("[SPEECH] Initialized: $_initialized");
    }
  }

  Future<String?> listenOnce() async {
    await init();

    if (!_initialized) return null;

    Completer<String?> completer = Completer();
    bool completed = false;

    _speech.listen(
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      cancelOnError: true,
      onResult: (result) {
        if (!completed && result.finalResult) {
          completed = true;
          completer.complete(result.recognizedWords);
        }
      },
    );

    _speech.statusListener = (status) {
      print("[SPEECH STATUS] $status");

      if (status == "done" && !completed) {
        completed = true;
        completer.complete(null);
      }
    };

    return completer.future;
  }

  Future<void> stop() async {
    await _speech.stop();
  }
}