// lib/features/braille/hardware_switch_service.dart
// MODULE 4 – Physical Switch Hardware Channel Interface
//
// Listens to 'sightmate/hardware_switches' EventChannel for raw switch events
// sent from MainActivity.kt's onKeyDown override.
//
// Switch identity encoding:
//   'UP'   = KEYCODE_VOLUME_UP   (Braille dot group A)
//   'DOWN' = KEYCODE_VOLUME_DOWN (Braille dot group B)
//
// Chord window: 400ms — consecutive presses within this window are
// grouped into a single Braille chord for decoding.

import 'dart:async';
import 'package:flutter/services.dart';

enum SwitchEvent { up, down }

class HardwareSwitchService {
  // Singleton
  static final HardwareSwitchService _instance = HardwareSwitchService._internal();
  factory HardwareSwitchService() => _instance;
  HardwareSwitchService._internal();

  static const EventChannel _switchChannel =
      EventChannel('sightmate/hardware_switches');

  static const MethodChannel _blindModeChannel =
      MethodChannel('sightmate/blind_mode');

  StreamSubscription<dynamic>? _sub;
  StreamController<SwitchEvent>? _controller;

  // ── Start listening ────────────────────────────────────────────────────────
  Stream<SwitchEvent> get switchStream {
    _controller ??= StreamController<SwitchEvent>.broadcast();
    _sub ??= _switchChannel.receiveBroadcastStream().listen((event) {
      if (event == 'UP') {
        _controller!.add(SwitchEvent.up);
      } else if (event == 'DOWN') {
        _controller!.add(SwitchEvent.down);
      }
    });
    return _controller!.stream;
  }

  // ── Set Blind Mode active/inactive on native side ─────────────────────────
  Future<void> setBlindMode(bool active) async {
    try {
      await _blindModeChannel.invokeMethod('setBlindMode', {'active': active});
    } on PlatformException {
      // Native not registered yet — degrade gracefully
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller?.close();
    _sub = null;
    _controller = null;
  }
}
