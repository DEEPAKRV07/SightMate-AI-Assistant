import 'package:flutter/material.dart';
import 'features/home/home_page.dart';
import 'shared/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize TTS once at app start
  await TTSService.init();

  runApp(const SightMateApp());
}

class SightMateApp extends StatelessWidget {
  const SightMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}