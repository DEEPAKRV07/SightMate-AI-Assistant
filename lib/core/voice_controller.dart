import 'package:flutter/material.dart';
import '../features/assistant/speech_service.dart';
import '../shared/tts_service.dart';
import 'app_router.dart';

class VoiceController {
  final SpeechService _speech = SpeechService();
  final _tts = TTSService(); // Singleton instance

  Future<void> listenAndRoute(BuildContext context) async {
    await _tts.speak('Listening');

    String? command = await _speech.listenOnce();

    if (command == null || command.trim().isEmpty) {
      return;
    }
    command = command.toLowerCase();

    if (command.contains('object') || command.contains('detect')) {
      AppRouter.goToObjectDetection(context);
    } else if (command.contains('read') || command.contains('text') || command.contains('scan')) {
      AppRouter.goToOCR(context);
    } else if (command.contains('translate') || command.contains('translation')) {
      AppRouter.goToTranslation(context);
    } else if (command.contains('navigation') || command.contains('navigate')) {
      AppRouter.goToNavigation(context);
    } else if (command.contains('system') || command.contains('battery')) {
      AppRouter.goToSystem(context);
    } else if (command.contains('braille') || command.contains('keyboard')) {
      AppRouter.goToBraille(context);
    } else {
      await _tts.speak('Command not recognized. Say: object, read, navigate, translate, or braille.');
    }
  }
}
