import 'package:flutter/material.dart';
import '../../shared/tts_service.dart';
import 'braille_service.dart';

class BraillePage extends StatefulWidget {
  const BraillePage({super.key});

  @override
  State<BraillePage> createState() => _BraillePageState();
}

class _BraillePageState extends State<BraillePage> {
  Set<int> activeDots = {};
  String typedText = "";

  void processCharacter() {
    String char = BrailleService.convertDots(activeDots);

    if (char.isEmpty) {
      activeDots.clear();
      setState(() {});

      return;
    }

    setState(() {
      typedText += char;
      activeDots.clear();
    });

    TTSService.speak(char);
  }

  Widget dotButton(int dot) {
    bool active = activeDots.contains(dot);

    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          activeDots.add(dot);
        });
      },
      onTapUp: (_) {
        processCharacter();
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: active ? Colors.green : Colors.grey.shade800,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            "$dot",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
            ),
          ),
        ),
      ),
    );
  }

  void addSpace() {
    setState(() {
      typedText += " ";
    });

    TTSService.speak("space");
  }

  void deleteChar() {
    if (typedText.isEmpty) return;

    setState(() {
      typedText = typedText.substring(0, typedText.length - 1);
    });

    TTSService.speak("delete");
  }

  void speakSentence() {
    if (typedText.isEmpty) return;

    TTSService.speak(typedText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Braille Keyboard"),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            addSpace();
          } else {
            deleteChar();
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! < 0) {
            speakSentence();
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                typedText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                dotButton(1),
                dotButton(4),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                dotButton(2),
                dotButton(5),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                dotButton(3),
                dotButton(6),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
              "Swipe Right → Space   |   Swipe Left → Delete   |   Swipe Up → Speak",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            )
          ],
        ),
      ),
    );
  }
}
