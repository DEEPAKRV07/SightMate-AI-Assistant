import 'package:flutter/material.dart';

import '../features/object_detection/object_detection_page.dart';
import '../features/ocr/ocr_page.dart';
import '../features/system/system_page.dart';
import '../features/translation/translate_page.dart';
import '../features/braille/braille_page.dart';


class AppRouter {


  static void goToObjectDetection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ObjectDetectionPage(),
      ),
    );
  }

  static void goToOCR(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OCRPage(),
      ),
    );
  }

  // For now navigation uses object detection mode
  static void goToNavigation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ObjectDetectionPage(),
      ),
    );
  }

  static void goToBraille(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BraillePage(),
      ),
    );
  }

  static void goToTranslation(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TranslatePage(),
      ),
    );
  }

  static void goToSystem(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SystemPage(),
      ),
    );
  }
}
