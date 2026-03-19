import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../shared/tts_service.dart';
import '../../core/permissions.dart';

class OCRPage extends StatefulWidget {
  const OCRPage({super.key});

  @override
  State<OCRPage> createState() => _OCRPageState();
}

class _OCRPageState extends State<OCRPage> {
  CameraController? _controller;
  late TextRecognizer _textRecognizer;

  bool _ready = false;
  bool _processing = false;
  bool _isSpeaking = false;

  List<TextLine> _lines = [];

  // ---------------------------------------------------
  // INIT
  // ---------------------------------------------------
  @override
  void initState() {
    super.initState();
    _textRecognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    _initCamera();
  }

  Future<void> _initCamera() async {
    print("[OCR] Initializing camera...");

    final hasPermission =
    await AppPermissions.requestCamera();

    if (!hasPermission) return;

    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
          (c) => c.lensDirection ==
          CameraLensDirection.back,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();

    setState(() => _ready = true);

    print("[OCR] Ready");
    await TTSService.speak(
        "OCR ready. Tap anywhere to scan.");
  }

  // ---------------------------------------------------
  // TAP → SCAN
  // ---------------------------------------------------
  Future<void> _scanNow() async {
    if (_processing || _isSpeaking) {
      print("[OCR] Busy...");
      return;
    }

    _processing = true;
    print("[OCR] Scan triggered");

    try {
      final file =
      await _controller!.takePicture();

      final inputImage =
      InputImage.fromFilePath(file.path);

      final result =
      await _textRecognizer.processImage(
          inputImage);

      if (result.text.trim().isEmpty) {
        await TTSService.speak(
            "No text detected.");
        _processing = false;
        return;
      }

      List<TextLine> validLines = [];

      for (final block in result.blocks) {
        for (final line in block.lines) {
          final cleaned =
          line.text.trim();

          if (cleaned.length < 2)
            continue;

          validLines.add(line);
          print(
              "[OCR] Line: ${line.text}");
        }
      }

      if (validLines.isEmpty) {
        await TTSService.speak(
            "No readable text.");
        _processing = false;
        return;
      }

      validLines.sort(
            (a, b) =>
            a.boundingBox.top
                .compareTo(
                b.boundingBox.top),
      );

      final fullText = validLines
          .map((l) => l.text.trim())
          .join(" ");

      print(
          "[OCR] FINAL TEXT: $fullText");

      _lines = validLines;

      await _controller?.pausePreview();
      setState(() {});

      _isSpeaking = true;

      await TTSService.speak(fullText);

      _isSpeaking = false;

      await _controller?.resumePreview();
    } catch (e) {
      print("[OCR ERROR] $e");
    }

    _processing = false;
  }

  // ---------------------------------------------------
  // DOUBLE TAP → RESCAN
  // ---------------------------------------------------
  Future<void> _rescan() async {
    print("[OCR] Rescan triggered");
    await TTSService.stop();
    await TTSService.speak("Rescanning.");
    await _scanNow();
  }

  // ---------------------------------------------------
  // SWIPE DOWN → STOP
  // ---------------------------------------------------
  Future<void> _stopReading() async {
    print("[OCR] Stop triggered");
    await TTSService.stop();
    _isSpeaking = false;
    _processing = false;
    await _controller?.resumePreview();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // ---------------------------------------------------
  // UI
  // ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (!_ready ||
        _controller == null ||
        !_controller!.value
            .isInitialized) {
      return const Scaffold(
        body: Center(
            child:
            CircularProgressIndicator()),
      );
    }

    final previewSize =
    _controller!.value.previewSize!;
    final screenSize =
        MediaQuery.of(context).size;

    final scaleX =
        screenSize.width /
            previewSize.height;
    final scaleY =
        screenSize.height /
            previewSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child:
            CameraPreview(_controller!),
          ),

          // FULL SCREEN TAP LAYER
          Positioned.fill(
            child: GestureDetector(
              behavior:
              HitTestBehavior.opaque,
              onTap: _scanNow,
              onDoubleTap: _rescan,
              onVerticalDragEnd: (_) =>
                  _stopReading(),
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),

          // Bounding boxes
          ..._lines.map((line) {
            final rect =
                line.boundingBox;

            return Positioned(
              left:
              rect.left * scaleX,
              top:
              rect.top * scaleY,
              width:
              rect.width * scaleX,
              height:
              rect.height *
                  scaleY,
              child: Container(
                decoration:
                BoxDecoration(
                  border: Border.all(
                    color:
                    Colors.green,
                    width: 2,
                  ),
                ),
              ),
            );
          }),

          const Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                "Tap: Scan | Double Tap: Rescan | Swipe Down: Stop",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}