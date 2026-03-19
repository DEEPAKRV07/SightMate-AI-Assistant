import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../../shared/tts_service.dart';
import '../../features/assistant/speech_service.dart';
import 'translate_service.dart';

class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {

  final SpeechService _speech = SpeechService();
  final TranslateService _translate = TranslateService();

  bool _translatorReady = false;
  bool _listening = false;
  bool _pageActive = true;

  String _lastTranslated = "";

  // ---------------------------------------------------
  // INIT
  // ---------------------------------------------------
  @override
  void initState() {
    super.initState();
    _initializeTranslator();
  }

  Future<void> _initializeTranslator() async {
    print("[TRANSLATE] Initializing...");

    await TTSService.speak("Preparing translator.");

    await _translate.init(
      source: TranslateLanguage.english,
      target: TranslateLanguage.tamil,
    );

    _translatorReady = true;

    await TTSService.speak(
        "Translation mode ready. Tap once to speak. Double tap to repeat. Swipe down to exit.");

    print("[TRANSLATE] Ready");
  }

  // ---------------------------------------------------
  // TAP → LISTEN ONCE
  // ---------------------------------------------------
  Future<void> _startListening() async {

    if (!_translatorReady || _listening) return;

    print("[TRANSLATE] Listening started");

    _listening = true;
    setState(() {});

    await TTSService.stop(); // stop any ongoing speech

    final spoken = await _speech.listenOnce();

    _listening = false;
    setState(() {});

    if (!_pageActive) return;

    if (spoken == null || spoken.trim().isEmpty) {
      await TTSService.speak("No speech detected.");
      return;
    }

    print("[TRANSLATE] Heard: $spoken");

    final translated =
    await _translate.translate(spoken);

    _lastTranslated = translated;

    print("[TRANSLATE] Translated: $translated");

    await TTSService.speak(translated);
  }

  // ---------------------------------------------------
  // DOUBLE TAP → REPEAT
  // ---------------------------------------------------
  Future<void> _repeat() async {
    if (_lastTranslated.isNotEmpty) {
      await TTSService.speak(_lastTranslated);
    } else {
      await TTSService.speak("Nothing to repeat.");
    }
  }

  // ---------------------------------------------------
  // SWIPE DOWN → EXIT
  // ---------------------------------------------------
  Future<void> _exit() async {
    print("[TRANSLATE] Exiting");

    _pageActive = false;
    _listening = false;

    await _speech.stop();
    await TTSService.stop();

    Navigator.pop(context);
  }

  // ---------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------
  @override
  void dispose() {
    _pageActive = false;
    _speech.stop();
    _translate.dispose();
    super.dispose();
  }

  // ---------------------------------------------------
  // UI
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _startListening,
        onDoubleTap: _repeat,
        onVerticalDragEnd: (_) => _exit(),
        child: Center(
          child: Text(
            _listening
                ? "Listening..."
                : "Translation Mode\n\nTap: Speak\nDouble Tap: Repeat\nSwipe Down: Exit",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
            ),
          ),
        ),
      ),
    );
  }
}