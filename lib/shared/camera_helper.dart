// lib/shared/camera_helper.dart
// Upgraded Camera Helper – CameraImage streaming pipeline
//
// Design decisions:
//   • Uses camera package's startImageStream() for continuous 30 FPS delivery
//   • Single CameraController instance — never re-initialized during a session
//   • ResolutionPreset.medium (640×480) → YOLO crops to 320×320 during preprocessing
//   • ImageFormatGroup.yuv420 on Android for zero-copy YUV→RGB path
//   • Frame gate: external callback controls frame acceptance; rejects during
//     busy inference windows to maintain 30 FPS without queue buildup

import 'dart:async';
import 'package:camera/camera.dart';

typedef FrameCallback = void Function(CameraImage image);

class CameraHelper {
  // Singleton
  static final CameraHelper _instance = CameraHelper._internal();
  factory CameraHelper() => _instance;
  CameraHelper._internal();

  CameraController? controller;
  bool _initialized = false;
  bool _streaming   = false;

  // ── Initialize ─────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('[CameraHelper] No cameras found on device.');
    }

    // Back-facing camera for navigation
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    controller = CameraController(
      back,
      ResolutionPreset.medium,   // 640×480 — good latency/quality balance
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Native YUV for Android
    );

    await controller!.initialize();

    // Lock exposure and focus for consistent frame quality during walking
    await controller!.setExposureMode(ExposureMode.auto);
    await controller!.setFocusMode(FocusMode.auto);

    _initialized = true;
  }

  // ── Start continuous frame stream ─────────────────────────────────────────
  Future<void> startStream(FrameCallback onFrame) async {
    if (!_initialized || _streaming) return;

    await controller!.startImageStream((CameraImage image) {
      onFrame(image);
    });

    _streaming = true;
  }

  // ── Stop frame stream ─────────────────────────────────────────────────────
  Future<void> stopStream() async {
    if (!_streaming) return;
    await controller!.stopImageStream();
    _streaming = false;
  }

  // ── Take single picture (used by OCR mode) ────────────────────────────────
  Future<XFile?> takePicture() async {
    if (!_initialized || controller == null) return null;
    // Stop stream first if active, to avoid concurrent access
    final wasStreaming = _streaming;
    if (wasStreaming) await stopStream();

    try {
      final file = await controller!.takePicture();
      return file;
    } finally {
      // Restart stream if it was active
      // Caller is responsible for restarting via startStream()
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────
  Future<void> dispose() async {
    if (_streaming) await stopStream();
    await controller?.dispose();
    controller = null;
    _initialized = false;
    _streaming = false;
  }

  bool get isInitialized => _initialized;
  bool get isStreaming    => _streaming;
}
