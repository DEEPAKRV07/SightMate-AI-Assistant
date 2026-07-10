// lib/features/braille/braille_page.dart
// MODULE 4 – Physical Switch Braille Keyboard Page
//
// Dual-mode interface:
//   • Touch Mode: existing dot-grid UI (retained for sighted helpers/testing)
//   • Blind Mode: hardware volume keys drive chord engine;
//     screen shows typed text as large high-contrast display only

import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/tts_service.dart';
import 'braille_service.dart';
import 'braille_chord_engine.dart';
import 'hardware_switch_service.dart';

class BraillePage extends StatefulWidget {
  const BraillePage({super.key});

  @override
  State<BraillePage> createState() => _BraillePageState();
}

class _BraillePageState extends State<BraillePage> {
  final _tts           = TTSService();
  final _switchSvc     = HardwareSwitchService();
  final _chordEngine   = BrailleChordEngine();

  bool _blindMode = false;
  String _typedText = '';
  Set<int> _activeDots = {};

  StreamSubscription<ChordResult>? _chordSub;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tts.init();
    _chordEngine.attachSwitchStream(_switchSvc.switchStream);
    _chordSub = _chordEngine.chordStream.listen(_onChordReceived);
  }

  @override
  void dispose() {
    _chordSub?.cancel();
    _switchSvc.setBlindMode(false);
    super.dispose();
  }

  // ── Chord handler ─────────────────────────────────────────────────────────

  void _onChordReceived(ChordResult chord) {
    setState(() {
      if (chord.character == '\b') {
        if (_typedText.isNotEmpty) {
          _typedText = _typedText.substring(0, _typedText.length - 1);
          _tts.speak('deleted');
        }
      } else if (chord.character == '\n') {
        _tts.speak(_typedText.isEmpty ? 'Empty' : _typedText);
      } else {
        _typedText += chord.character;
        _tts.speak(chord.character);
      }
    });
  }

  // ── Toggle blind mode ─────────────────────────────────────────────────────

  Future<void> _toggleBlindMode() async {
    final newMode = !_blindMode;
    setState(() => _blindMode = newMode);
    await _switchSvc.setBlindMode(newMode);

    if (newMode) {
      await _tts.speak(
        'Blind mode active. Volume Up and Down keys now control Braille input. '
        'Press Volume Up for dot group one, Volume Down for dot group two. '
        'Characters are entered when no key is pressed for 400 milliseconds.',
      );
    } else {
      await _tts.speak('Blind mode off. Touch mode active.');
    }
  }

  // ── Touch mode: existing dot grid ─────────────────────────────────────────

  void _processTouchCharacter() {
    final char = BrailleService.convertDots(_activeDots);
    if (char.isEmpty) {
      _activeDots.clear();
      setState(() {});
      return;
    }
    setState(() {
      _typedText += char;
      _activeDots.clear();
    });
    _tts.speak(char);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTextDisplay(),
            const Spacer(),
            _blindMode ? _buildBlindModeGuide() : _buildDotGrid(),
            _buildActionRow(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
        ),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      child: Row(
        children: [
          const Icon(Icons.accessible, color: Color(0xFF00D4FF), size: 22),
          const SizedBox(width: 10),
          const Text(
            'Braille Keyboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Blind mode toggle
          GestureDetector(
            onTap: _toggleBlindMode,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _blindMode
                    ? const Color(0xFF00D4FF)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF00D4FF),
                  width: 1,
                ),
              ),
              child: Text(
                _blindMode ? 'BLIND ON' : 'BLIND OFF',
                style: TextStyle(
                  color: _blindMode ? Colors.black : const Color(0xFF00D4FF),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextDisplay() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Typed Text',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _typedText.isEmpty ? '─' : _typedText,
            style: TextStyle(
              color: _typedText.isEmpty ? Colors.white24 : Colors.white,
              fontSize: _blindMode ? 28 : 22,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlindModeGuide() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4FF).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.volume_up, color: Color(0xFF00D4FF), size: 40),
          const SizedBox(height: 12),
          const Text(
            'Hardware Switch Mode Active',
            style: TextStyle(
              color: Color(0xFF00D4FF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vol+ = Dot Group A   |   Vol− = Dot Group B\n'
            'Hold pattern for 400ms to confirm character',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _switchIndicator('UP', SwitchEvent.up),
              _switchIndicator('DOWN', SwitchEvent.down),
            ],
          ),
        ],
      ),
    );
  }

  Widget _switchIndicator(String label, SwitchEvent type) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white30, width: 1.5),
          ),
          child: Center(
            child: Icon(
              type == SwitchEvent.up ? Icons.arrow_upward : Icons.arrow_downward,
              color: Colors.white60,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildDotGrid() {
    // Standard Braille 2×3 dot layout
    const dotNumbers = [
      [1, 4],
      [2, 5],
      [3, 6],
    ];

    return Column(
      children: dotNumbers.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((dot) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _dotButton(dot),
            )).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _dotButton(int dot) {
    final active = _activeDots.contains(dot);
    return GestureDetector(
      onTapDown: (_) => setState(() => _activeDots.add(dot)),
      onTapUp:   (_) => _processTouchCharacter(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? const Color(0xFF00D4FF)
              : const Color(0xFF1A1A2E),
          border: Border.all(
            color: active
                ? const Color(0xFF00D4FF)
                : Colors.white24,
            width: 2,
          ),
          boxShadow: active
              ? [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4), blurRadius: 12)]
              : [],
        ),
        child: Center(
          child: Text(
            '$dot',
            style: TextStyle(
              color: active ? Colors.black : Colors.white60,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _actionButton(
              label: 'Space',
              icon: Icons.space_bar,
              onTap: () {
                setState(() => _typedText += ' ');
                _tts.speak('space');
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionButton(
              label: 'Read',
              icon: Icons.record_voice_over,
              onTap: () => _tts.speak(_typedText.isEmpty ? 'Nothing typed' : _typedText),
              primary: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionButton(
              label: 'Clear',
              icon: Icons.clear,
              onTap: () {
                setState(() => _typedText = '');
                _tts.speak('Cleared');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
                )
              : null,
          color: primary ? null : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: primary ? null : Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: primary ? Colors.black : Colors.white70, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: primary ? Colors.black : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
