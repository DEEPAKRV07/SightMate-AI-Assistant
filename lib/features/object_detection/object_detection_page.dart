// lib/features/object_detection/object_detection_page.dart
// MODULE 1 – Reactive Edge Vision Pipeline: 30 FPS Object Detection Page
//
// Architecture:
//   • startImageStream() drives the processing loop at camera frame rate
//   • _busy flag: frame dropped if previous inference still running
//   • H-Splitter: classifies each detection into spatial zones
//   • Motion Echo Filter: Dart-side ego-motion compensation
//   • TTS: urgent path for hazards in Area 3; normal path for peripherals
//   • Speech cooldown: 2.5s minimum between identical alerts
//   • DeepLabV3 segmentation REMOVED — replaced by H-Splitter geometry

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../shared/camera_helper.dart';
import '../../shared/tts_service.dart';
import 'yolo_service.dart';
import 'h_splitter.dart';
import 'motion_echo_filter.dart';
import 'overlay_painter.dart';

class ObjectDetectionPage extends StatefulWidget {
  const ObjectDetectionPage({super.key});

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage>
    with WidgetsBindingObserver {

  final _camera        = CameraHelper();
  final _yolo          = YoloService();
  final _tts           = TTSService();
  final _motionFilter  = MotionEchoFilter();

  bool _ready   = false;
  bool _busy    = false;
  bool _running = false;

  // Detection state
  List<DetectionResult> _latestDetections   = [];
  List<DetectionResult> _previousDetections = [];
  Uint8List?            _prevYFrame;
  Offset?               _vanishingPoint; // Dynamic vanishing point from motion flow

  // Speech deduplication
  final Map<String, DateTime> _lastSpokenByLabel = {};
  static const Duration _speechCooldown = Duration(milliseconds: 2500);

  // Frame dimensions (set once camera is initialized)
  double _frameWidth  = 640;
  double _frameHeight = 480;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _tts.init();
    await _camera.initialize();
    await _yolo.loadModel();

    if (_camera.controller != null) {
      _frameWidth  = _camera.controller!.value.previewSize?.height ?? 640;
      _frameHeight = _camera.controller!.value.previewSize?.width  ?? 480;
    }

    setState(() => _ready = true);
    await _tts.speak('Navigation mode ready. Point camera forward.');
    _startStream();
  }

  void _startStream() {
    if (_running) return;
    _running = true;

    _camera.startStream((CameraImage image) {
      if (!_busy) {
        _busy = true;
        _processFrame(image).whenComplete(() => _busy = false);
      }
      // If _busy: frame dropped → next frame will be processed
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _camera.stopStream();
      _running = false;
    } else if (state == AppLifecycleState.resumed && _ready) {
      _startStream();
    }
  }

  @override
  void dispose() {
    _running = false;
    _camera.stopStream();
    _yolo.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Core processing pipeline ───────────────────────────────────────────────

  Future<void> _processFrame(CameraImage image) async {
    // 1. YOLO inference
    final detections = await _yolo.detectFromCameraImage(image);
    if (detections == null) return;

    // 2. Extract Y plane for ego-motion computation
    final currYFrame = Uint8List.fromList(image.planes[0].bytes);
    EgoMotionResult egoMotion = EgoMotionResult.zero;

    if (_prevYFrame != null) {
      egoMotion = await _motionFilter.computeEgoMotion(
        prevFrame:    _prevYFrame!,
        currFrame:    currYFrame,
        width:        image.planes[0].bytesPerRow,
        height:       image.height,
      );
    }
    _prevYFrame = currYFrame;

    // 3. Motion echo filter: identify genuinely moving hazards
    final filtered = _motionFilter.applyFilter(
      prevDetections: _previousDetections,
      currDetections: detections,
      egoMotion:      egoMotion,
    );

    // 4. Update dynamic vanishing point if reliable motion is estimated
    if (egoMotion.isReliable) {
      _vanishingPoint = Offset(egoMotion.vpX, egoMotion.vpY);
    } else {
      _vanishingPoint = null; // Fallback to static center
    }

    // 5. H-Splitter: zone-classify detections
    final zoned = HSplitter.classify(
      detections:     detections,
      frameWidth:     _frameWidth,
      frameHeight:    _frameHeight,
      vanishingPoint: _vanishingPoint,
    );

    // 5. Update overlay
    if (mounted) {
      setState(() {
        _latestDetections   = detections;
        _previousDetections = List.from(detections);
      });
    }

    // 6. TTS alerts — apply cooldown and priority routing
    await _generateAlerts(zoned, filtered);
  }

  Future<void> _generateAlerts(
    List<ZonedDetection>   zoned,
    List<FilteredDetection> filtered,
  ) async {
    // Separate hazards by urgency
    final urgentAlerts  = <String>[];
    final normalAlerts  = <String>[];

    for (final zd in zoned) {
      if (!zd.shouldAlert) continue;

      final label = zd.detection.label;
      final now   = DateTime.now();
      final last  = _lastSpokenByLabel[label];

      if (last != null && now.difference(last) < _speechCooldown) continue;
      _lastSpokenByLabel[label] = now;

      final isMoving = filtered
          .where((fd) => fd.detection.label == label)
          .any((fd) => fd.isGenuinelyMoving);

      final phrase = _buildPhrase(label, zd.zone, isMoving);

      if (zd.zone == SpatialZone.centralPath && isMoving) {
        urgentAlerts.add(phrase);
      } else {
        normalAlerts.add(phrase);
      }
    }

    // Urgent path: immediate interrupt for central hazards
    for (final alert in urgentAlerts) {
      await _tts.speakUrgent(alert);
    }

    // Normal path: queue peripheral alerts
    for (final alert in normalAlerts) {
      await _tts.speak(alert);
    }
  }

  String _buildPhrase(String label, SpatialZone zone, bool isMoving) {
    final zoneStr = zone == SpatialZone.centralPath ? 'immediate front'
                  : zone == SpatialZone.leftFlank   ? 'left side'
                  : 'right side';

    final motion  = isMoving ? 'moving ' : '';
    return '${motion}${label}, ${zoneStr}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ready ? _buildCamera() : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.cyanAccent),
          SizedBox(height: 20),
          Text(
            'Initializing Vision Pipeline…',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera unavailable', style: TextStyle(color: Colors.white)));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        CameraPreview(controller),

        // H-Splitter trapezoid overlay
        CustomPaint(
          painter: _TrapezoidPainter(
            frameWidth:     _frameWidth,
            frameHeight:    _frameHeight,
            vanishingPoint: _vanishingPoint,
          ),
        ),

        // Detection bounding boxes
        CustomPaint(
          painter: OverlayPainter(
            detections:     _latestDetections,
            frameWidth:     _frameWidth,
            frameHeight:    _frameHeight,
            vanishingPoint: _vanishingPoint,
          ),
        ),

        // Status bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildStatusBar(),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.black54,
      child: SafeArea(
        child: Row(
          children: [
            const Icon(Icons.videocam, color: Colors.cyanAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              'Live · ${_latestDetections.length} object${_latestDetections.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const Spacer(),
            const _FpsBadge(),
          ],
        ),
      ),
    );
  }
}

// ─── Trapezoid overlay painter (H-Splitter zone visualization) ───────────────

class _TrapezoidPainter extends CustomPainter {
  final double frameWidth;
  final double frameHeight;
  final Offset? vanishingPoint;

  const _TrapezoidPainter({
    required this.frameWidth,
    required this.frameHeight,
    this.vanishingPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Scale trapezoid from frame to screen coordinates
    final scaleX = size.width  / frameWidth;
    final scaleY = size.height / frameHeight;

    final path = HSplitter.trapezoidPath(frameWidth, frameHeight, vanishingPoint);

    // Apply scale transform
    final scaledPath = path.transform(
      Matrix4.diagonal3Values(scaleX, scaleY, 1.0).storage,
    );

    canvas.drawPath(scaledPath, paint);
    canvas.drawPath(scaledPath, strokePaint);

    // Draw dynamic horizon line and vanishing point circle for debug visual
    if (vanishingPoint != null) {
      final vpScreen = Offset(
        vanishingPoint!.dx * size.width,
        vanishingPoint!.dy * size.height,
      );

      // Draw horizon line
      final horizonPaint = Paint()
        ..color = Colors.redAccent.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(0, vpScreen.dy),
        Offset(size.width, vpScreen.dy),
        horizonPaint,
      );

      // Draw vanishing point center
      final vpPaint = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(vpScreen, 4.0, vpPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrapezoidPainter old) =>
      old.vanishingPoint != vanishingPoint;
}

// ─── FPS badge ───────────────────────────────────────────────────────────────

class _FpsBadge extends StatefulWidget {
  const _FpsBadge();

  @override
  State<_FpsBadge> createState() => _FpsBadgeState();
}

class _FpsBadgeState extends State<_FpsBadge> {
  int _fps = 0;
  int _frameCount = 0;
  DateTime _lastCheck = DateTime.now();

  void _tick() {
    _frameCount++;
    final now = DateTime.now();
    if (now.difference(_lastCheck).inSeconds >= 1) {
      setState(() {
        _fps = _frameCount;
        _frameCount = 0;
        _lastCheck = now;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _fps >= 25 ? Colors.green.withOpacity(0.7) : Colors.orange.withOpacity(0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$_fps FPS',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
