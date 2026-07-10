// lib/shared/tts_service.dart
// MODULE 3 – Human-like Pacing Text-to-Speech Engine
//
// Architecture:
//   • Async token scheduling queue (StreamController<_TtsTask>)
//   • Punctuation Interceptor: period→550ms, comma→250ms, segment→350ms
//   • Priority interrupt: hazard alerts flush queue and speak immediately
//   • Single FlutterTts instance — never instantiated twice

import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';

// ─── Internal task type ──────────────────────────────────────────────────────

enum _TtsPriority { normal, urgent }

class _TtsTask {
  final String text;
  final _TtsPriority priority;
  _TtsTask(this.text, this.priority);
}

// ─── TTSService ───────────────────────────────────────────────────────────────

class TTSService {
  // Singleton
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  // ── Engine ──────────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;

  // ── Queue ───────────────────────────────────────────────────────────────────
  final _queue = StreamController<_TtsTask>.broadcast();
  StreamSubscription<_TtsTask>? _sub;
  final List<_TtsTask> _pending = [];

  // ── Micro-gap constants (ms) ─────────────────────────────────────────────────
  static const int _gapPeriod  = 550;   // Full stop / terminal punctuation
  static const int _gapComma   = 250;   // Mid-sentence comma pause
  static const int _gapSegment = 350;   // General segment boundary

  // ── Hazard priority phrases ───────────────────────────────────────────────
  static const Set<String> _hazardKeywords = {
    'obstacle', 'hazard', 'warning', 'danger', 'stop', 'veer', 'caution',
  };

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);   // Highly intelligible human-like pace
    await _tts.setPitch(1.0);         // Neutral clear pitch
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    _tts.setCompletionHandler(() {
      _speaking = false;
      _processNext();
    });

    _tts.setCancelHandler(() {
      _speaking = false;
    });

    _sub = _queue.stream.listen((task) {
      _pending.add(task);
      if (!_speaking) _processNext();
    });

    _initialized = true;
  }

  // ── Speak (normal priority) ───────────────────────────────────────────────
  Future<void> speak(String text) async {
    if (!_initialized) await init();
    if (text.trim().isEmpty) return;
    _queue.add(_TtsTask(text.trim(), _TtsPriority.normal));
  }

  // ── Urgent speak: flushes queue, speaks immediately (collision warning) ───
  Future<void> speakUrgent(String text) async {
    if (!_initialized) await init();
    if (text.trim().isEmpty) return;

    // Drain pending queue
    _pending.clear();
    await _tts.stop();
    _speaking = false;

    // Insert urgent task at front
    _pending.insert(0, _TtsTask(text.trim(), _TtsPriority.urgent));
    _processNext();
  }

  // ── Stop all ─────────────────────────────────────────────────────────────
  Future<void> stop() async {
    _pending.clear();
    await _tts.stop();
    _speaking = false;
  }

  // ── Internal: process next task in queue ──────────────────────────────────
  void _processNext() {
    if (_speaking || _pending.isEmpty) return;
    final task = _pending.removeAt(0);
    _speakWithPacing(task.text);
  }

  // ── Punctuation interceptor + micro-gap engine ────────────────────────────
  Future<void> _speakWithPacing(String rawText) async {
    _speaking = true;

    // Segment on structural punctuation boundaries
    final segments = _tokenize(rawText);

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.text.isEmpty) continue;

      await _tts.speak(seg.text);
      // _tts.awaitSpeakCompletion(true) blocks until done

      if (i < segments.length - 1 && seg.pauseAfterMs > 0) {
        await Future.delayed(Duration(milliseconds: seg.pauseAfterMs));
      }
    }

    _speaking = false;
    _processNext();
  }

  // ── Tokenizer: splits on punctuation and assigns pause durations ───────────
  List<_Segment> _tokenize(String text) {
    final List<_Segment> result = [];
    // Pattern: split keeping delimiters
    final RegExp boundary = RegExp(r'([.!?]|,|;|:)');

    int cursor = 0;
    final matches = boundary.allMatches(text).toList();

    for (final m in matches) {
      final before = text.substring(cursor, m.start).trim();
      final punct  = m.group(0)!;
      cursor = m.end;

      if (before.isNotEmpty) {
        final pause = _pauseForPunct(punct);
        result.add(_Segment(before + punct, pause));
      }
    }

    // Remaining text after last punctuation
    final tail = text.substring(cursor).trim();
    if (tail.isNotEmpty) {
      result.add(_Segment(tail, 0));
    }

    // If no segments were created, just return the full text
    if (result.isEmpty) {
      result.add(_Segment(text, 0));
    }

    return result;
  }

  int _pauseForPunct(String p) {
    switch (p) {
      case '.':
      case '!':
      case '?':
        return _gapPeriod;
      case ',':
      case ';':
        return _gapComma;
      case ':':
        return _gapSegment;
      default:
        return 0;
    }
  }

  bool _isHazardText(String text) {
    final lower = text.toLowerCase();
    return _hazardKeywords.any((kw) => lower.contains(kw));
  }

  // ── Dispose ───────────────────────────────────────────────────────────────
  void dispose() {
    _sub?.cancel();
    _queue.close();
    _tts.stop();
  }
}

// ─── Internal data class ─────────────────────────────────────────────────────

class _Segment {
  final String text;
  final int pauseAfterMs;
  _Segment(this.text, this.pauseAfterMs);
}