import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslateService {
  OnDeviceTranslator? _translator;

  Future<void> init({
    required TranslateLanguage source,
    required TranslateLanguage target,
  }) async {
    _translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
  }

  Future<String> translate(String text) async {
    if (_translator == null) {
      throw Exception("Translator not initialized");
    }

    return await _translator!.translateText(text);
  }

  void dispose() {
    _translator?.close();
  }
}