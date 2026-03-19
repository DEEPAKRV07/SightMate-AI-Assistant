import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/tts_service.dart';
import '../system/battery_service.dart';
import 'speech_service.dart';

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  final SpeechService _speech = SpeechService();
  final BatteryService _battery = BatteryService();

  String text = "Tap mic and speak";

  void _handleCommand(String command) async {
    command = command.toLowerCase();

    if (command.contains("battery")) {
      final level = await _battery.getBatteryLevel();

      await TTSService.speak("Battery level is $level percent");
    }
    else if (command.contains("time")) {
      final time = DateFormat('hh:mm a').format(DateTime.now());
      await TTSService.speak("Current time is $time");
    }
    else if (command.contains("date")) {
      final date = DateFormat('EEEE, MMMM d').format(DateTime.now());
      await TTSService.speak("Today is $date");
    }
    else {
      await TTSService.speak("Command not recognized");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Voice Assistant")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            FloatingActionButton(
              onPressed: () async {
                String? command = await _speech.listenOnce();

                if (command == null || command.trim().isEmpty) {
                  return;
                }
                setState(() => text = command);
                _handleCommand(command);
              },
              child: const Icon(Icons.mic),
            ),
          ],
        ),
      ),
    );
  }
}
