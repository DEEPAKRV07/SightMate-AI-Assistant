import 'package:flutter/material.dart';
import '../features/assistant/speech_service.dart';
import '../shared/tts_service.dart';
import 'app_router.dart';

class VoiceController {
  final SpeechService _speech = SpeechService();

  Future<void> listenAndRoute(BuildContext context) async {
    await TTSService.speak("Listening");

    String? command = await _speech.listenOnce();

    if (command == null || command.trim().isEmpty) {
      return;
    }
    command = command.toLowerCase();

    if (command.contains("object")) {
      AppRouter.goToObjectDetection(context);
    } else if (command.contains("read") || command.contains("text")) {
      AppRouter.goToOCR(context);
    } else if (command.contains("translate") ||
        command.contains("translation")) {
      AppRouter.goToTranslation(context);
    } else if (command.contains("navigation")) {
      AppRouter.goToNavigation(context);
    } else if (command.contains("system")) {
      AppRouter.goToSystem(context);
    } else if (command.contains("braille keyboard")) {
      AppRouter.goToBraille(context);
    } else {
      await TTSService.speak("Command not recognized");
    }
  }
}
