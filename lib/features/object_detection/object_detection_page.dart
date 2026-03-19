import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../shared/camera_helper.dart';
import '../../shared/tts_service.dart';

import 'yolo_service.dart';
import 'overlay_painter.dart';

import '../navigation/segmentation_service.dart';
import '../navigation/navigation_fusion_service.dart';
import '../navigation/segmentation_overlay.dart';

class ObjectDetectionPage extends StatefulWidget {
  const ObjectDetectionPage({super.key});

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage>
    with WidgetsBindingObserver {
  final CameraHelper _camera = CameraHelper();
  final YoloService _yolo = YoloService();
  final SegmentationService _segmentation = SegmentationService();
  final NavigationFusionService _fusion = NavigationFusionService();

  bool _ready = false;
  bool _busy = false;
  bool _navigationMode = false;

  Timer? _navTimer;

  List<DetectionResult> _latestDetections = [];
  List<List<int>> _latestSegMask = [];

  String _lastSpokenText = "";
  DateTime _lastSpeechTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    print("[SYSTEM] Initializing camera...");
    await _camera.initialize();

    print("[SYSTEM] Loading YOLO...");
    await _yolo.loadModel();

    print("[SYSTEM] Loading segmentation...");
    await _segmentation.loadModel();

    print("[SYSTEM] System ready");

    setState(() {
      _ready = true;
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _camera.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// SINGLE DETECTION
  Future<void> _singleDetect() async {
    if (_busy) return;

    _busy = true;

    final file = await _camera.takePicture();

    if (file == null) {
      _busy = false;
      return;
    }

    final detections = await _yolo.detectFromFile(file.path);

    setState(() {
      _latestDetections = detections;
    });

    print("[YOLO] detections: ${detections.length}");

    if (detections.isEmpty) {
      _speak("Nothing detected");
      _busy = false;
      return;
    }

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final top = detections.first;

    String direction = "in front";

    if (top.rect.center.dx < 0.3) direction = "on your left";
    if (top.rect.center.dx > 0.7) direction = "on your right";

    _speak("I see ${top.label} $direction");

    _busy = false;
  }

  /// START NAVIGATION
  void _startNavigation() {
    if (_navigationMode) return;

    print("===== NAVIGATION STARTED =====");

    _navigationMode = true;

    _navTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (timer) async {
        if (!_navigationMode || _busy) return;

        _busy = true;

        print("[NAV] capturing frame");

        final file = await _camera.takePicture();

        if (file == null) {
          _busy = false;
          return;
        }

        /// YOLO detection
        final detections = await _yolo.detectFromFile(file.path);

        /// segmentation
        final segMask = await _segmentation.runSegmentation(file.path);

        final segZones = _segmentation.analyzeWalkable(segMask);

        setState(() {
          _latestDetections = detections;
          _latestSegMask = segMask.isEmpty ? [] : segMask;
        });

        /// navigation fusion
        String message = _fusion.decideNavigation(
          detections,
          segZones["center"] ?? 0,
          segZones["left"] ?? 0,
          segZones["right"] ?? 0,
        );

        print("[NAV] decision → $message");

        _speak(message);

        _busy = false;
      },
    );

    _speak("Navigation started");

    setState(() {});
  }

  void _stopNavigation() {
    print("[NAV] Navigation stopped");

    _navigationMode = false;

    _navTimer?.cancel();

    _speak("Navigation stopped");

    setState(() {});
  }

  /// SPEECH
  Future<void> _speak(String text) async {
    final now = DateTime.now();

    if (text == _lastSpokenText &&
        now.difference(_lastSpeechTime).inMilliseconds < 2000) {
      return;
    }

    _lastSpeechTime = now;
    _lastSpokenText = text;

    print("[SPEECH] $text");

    await TTSService.speak(text);
  }

  /// UI
  @override
  Widget build(BuildContext context) {
    if (!_ready ||
        _camera.controller == null ||
        !_camera.controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// CAMERA
          Positioned.fill(
            child: CameraPreview(_camera.controller!),
          ),

          /// SEGMENTATION OVERLAY
          Positioned.fill(
            child: CustomPaint(
              painter: SegmentationOverlay(_latestSegMask),
            ),
          ),

          /// YOLO BOXES
          Positioned.fill(
            child: CustomPaint(
              painter: OverlayPainter(_latestDetections),
            ),
          ),

          /// DETECT BUTTON
          Positioned(
            bottom: 30,
            left: 20,
            child: FloatingActionButton(
              heroTag: "detect",
              onPressed: _singleDetect,
              child: const Icon(Icons.search),
            ),
          ),

          /// NAVIGATION BUTTON
          Positioned(
            bottom: 30,
            right: 20,
            child: FloatingActionButton(
              heroTag: "nav",
              backgroundColor: _navigationMode ? Colors.red : Colors.green,
              onPressed: _navigationMode ? _stopNavigation : _startNavigation,
              child: Icon(
                _navigationMode ? Icons.stop : Icons.navigation,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
