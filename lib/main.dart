import 'package:flutter/material.dart';
import 'features/home/home_page.dart';
import 'shared/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize TTS singleton once at app start
  await TTSService().init();

  runApp(const SightMateApp());
}

class SightMateApp extends StatelessWidget {
  const SightMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SightMate',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A14),
        colorScheme: const ColorScheme.dark(
          primary:   Color(0xFF00D4FF),
          secondary: Color(0xFF0077AA),
        ),
      ),
      home: const HomePage(),
    );
  }
}