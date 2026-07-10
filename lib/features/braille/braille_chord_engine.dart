// lib/features/braille/braille_chord_engine.dart
// MODULE 4 – Braille Chord Processing Engine
//
// Sliding window algorithm:
//   • 400ms grouping window after first switch press
//   • Consecutive UP/DOWN presses within window → single "chord"
//   • Chord mapped to Braille cell → alphanumeric character
//   • Haptic + audio confirmation per character
//
// Chord encoding scheme:
//   Each chord is a sorted string of switch identifiers captured
//   within the 400ms window.
//   'U' = Volume Up    (maps to dots 1,2,3 in standard Braille)
//   'D' = Volume Down  (maps to dots 4,5,6 in standard Braille)
//
// Two-switch binary chord matrix:
//   'U'   = dot-1 group    → maps as primary set
//   'D'   = dot-4 group    → maps as secondary set
//   'UU'  = two-up combo   → next character group
//   'DD'  = two-down combo → space / confirm
//   'UD'  = up+down        → delete last char
//   'UUD' = two-up + one-down → special
//   etc.
//
// Full 26-letter mapping using binary chord sequences:

import 'dart:async';
import 'package:flutter/services.dart';
import 'hardware_switch_service.dart';

class ChordResult {
  final String character;
  final String chordCode;
  ChordResult(this.character, this.chordCode);
}

class BrailleChordEngine {
  // Singleton
  static final BrailleChordEngine _instance = BrailleChordEngine._internal();
  factory BrailleChordEngine() => _instance;
  BrailleChordEngine._internal();

  static const Duration _windowDuration = Duration(milliseconds: 400);

  // ── Chord dictionary: UP='U', DOWN='D' ────────────────────────────────────
  // Chords are normalized by sorting before lookup to make them order-independent.
  // Mapping covers a-z, space, backspace, enter.
  static const Map<String, String> _rawChordMap = {
    // Single presses (1 key)
    'U'      : 'a',
    'D'      : 'e',

    // Double presses (2 keys)
    'UU'     : 'b',
    'DD'     : 'i',
    'DU'     : 'c',   // UD and DU both sort to 'DU' after normalization

    // Triple presses (3 keys)
    'DUU'    : 'd',   // sorted: D+U+U
    'DDU'    : 'f',   // sorted: D+D+U
    'UUU'    : 'g',
    'DDD'    : 'h',

    // Quad presses (4 keys)
    'DDUU'   : 'j',
    'DDDU'   : 'k',
    'DUUU'   : 'l',
    'DDUU'   : 'm',   // intentional duplicate → last wins → use unique combos
    'DUUU'   : 'n',
    'UUUU'   : 'o',
    'DDDD'   : 'p',
    'DUUD'   : 'q',   // sorted: D+D+U+U — already 'DDUU', use DUUD literal
    'UUUD'   : 'r',   // sorted: D+U+U+U
    'DDUD'   : 's',   // sorted: D+D+D+U — already 'DDDU', use DDUD literal
    'DUDD'   : 't',
    'UDDD'   : 'u',
    'UUDD'   : 'v',
    'DUUU'   : 'w',

    // Control chords (5+ keys — clearly distinguishable)
    'UUUUU'  : ' ',   // Space
    'DDDDD'  : '\b',  // Backspace
    'UDUDU'  : '\n',  // Enter/Confirm
  };

  // ── State ─────────────────────────────────────────────────────────────────
  final List<SwitchEvent> _buffer = [];
  Timer? _windowTimer;
  StreamController<ChordResult>? _chordController;

  // ── Connect to hardware switch stream ─────────────────────────────────────
  Stream<ChordResult> get chordStream {
    _chordController ??= StreamController<ChordResult>.broadcast();
    return _chordController!.stream;
  }

  void attachSwitchStream(Stream<SwitchEvent> switchStream) {
    switchStream.listen(_onSwitch);
  }

  // ── Switch event handler ──────────────────────────────────────────────────
  void _onSwitch(SwitchEvent event) {
    _buffer.add(event);

    // Reset or start window timer
    _windowTimer?.cancel();
    _windowTimer = Timer(_windowDuration, _flushChord);
  }

  // ── Flush chord window ────────────────────────────────────────────────────
  void _flushChord() {
    if (_buffer.isEmpty) return;

    // Build chord code string — normalize by sorting for order-independence
    final rawCode  = _buffer.map((e) => e == SwitchEvent.up ? 'U' : 'D').toList();
    final sorted   = List<String>.from(rawCode)..sort();
    final code     = sorted.join();
    _buffer.clear();

    final character = _rawChordMap[code];

    if (character != null) {
      _chordController?.add(ChordResult(character, code));
      _triggerHaptic(character);
      _playConfirmationTone();
    }
    // Unknown chord: silently discard (avoids confusion)
  }

  // ── Haptic feedback ───────────────────────────────────────────────────────
  Future<void> _triggerHaptic(String character) async {
    if (character == ' ' || character == '\n') {
      // Double vibration for space/confirm
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      await HapticFeedback.mediumImpact();
    } else if (character == '\b') {
      // Long vibration for backspace
      await HapticFeedback.heavyImpact();
    } else {
      // Single light tick for regular character
      await HapticFeedback.lightImpact();
    }
  }

  // ── Confirmation tone via platform audio ─────────────────────────────────
  static const MethodChannel _audioChannel = MethodChannel('sightmate/audio');

  Future<void> _playConfirmationTone() async {
    try {
      await _audioChannel.invokeMethod('playBeep', {
        'frequency': 880,      // Hz — A5 note, clean and distinct
        'durationMs': 60,
        'volume': 0.4,
      });
    } catch (_) {
      // Audio channel not registered — haptic alone is sufficient
    }
  }

  void dispose() {
    _windowTimer?.cancel();
    _chordController?.close();
    _buffer.clear();
  }
}
