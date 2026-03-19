import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/voice_controller.dart';
import '../../core/app_router.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final VoiceController _voice = VoiceController();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        _voice.listenAndRoute(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // MAIN BUTTON COLUMN
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  children: [
                    _buildButton(
                      context,
                      label: "Object Detection",
                      braille: "⠕",
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppRouter.goToObjectDetection(
                            context);
                      },
                    ),

                    const SizedBox(height: 20),

                    _buildButton(
                      context,
                      label: "Read Text",
                      braille: "⠗",
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppRouter.goToOCR(context);
                      },
                    ),

                    const SizedBox(height: 20),

                    _buildButton(
                      context,
                      label: "Translate",
                      braille: "⠞",
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppRouter.goToTranslation(context);
                      },
                    ),

                    const SizedBox(height: 20),

                    _buildButton(
                      context,
                      label: "Navigation",
                      braille: "⠝",
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppRouter.goToNavigation(
                            context);
                      },
                    ),

                    const SizedBox(height: 20),

                    _buildButton(
                      context,
                      label: "Braille Keyboard",
                      braille: "⠃",
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppRouter.goToBraille(context);
                      },
                    ),

                    const SizedBox(height: 20),


                    _buildButton(
                      context,
                      label: "System Info",
                      braille: "⠎",
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AppRouter.goToSystem(context);
                      },
                    ),
                  ],
                ),
              ),

              // LARGE BOTTOM CENTER MIC
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      _voice.listenAndRoute(context);
                    },
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white
                                .withOpacity(0.3),
                            blurRadius: 15,
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.mic,
                        size: 36,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(
      BuildContext context, {
        required String label,
        required String braille,
        required VoidCallback onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            vertical: 22, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
          BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment:
          MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              braille,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
