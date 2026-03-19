import 'package:camera/camera.dart';

class CameraHelper {
  CameraController? controller;

  bool _initialized = false;
  bool _capturing = false;

  /// INITIALIZE CAMERA
  Future<void> initialize() async {
    if (_initialized) return;

    final cameras = await availableCameras();

    controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();

    _initialized = true;

    print("[CAMERA] Initialized successfully");
  }

  /// TAKE PICTURE (USED BY OBJECT DETECTION)
  Future<XFile?> takePicture() async {
    if (controller == null || !controller!.value.isInitialized || _capturing) {
      return null;
    }

    try {
      _capturing = true;

      final file = await controller!.takePicture();

      _capturing = false;

      return file;
    } catch (e) {
      print("[CAMERA ERROR] $e");

      _capturing = false;

      return null;
    }
  }

  /// CAMERA STREAM (OPTIONAL FUTURE UPGRADE)
  void startStream(Function(CameraImage) onFrame) {
    if (controller == null) return;

    controller!.startImageStream((image) {
      onFrame(image);
    });

    print("[CAMERA] stream started");
  }

  void stopStream() {
    controller?.stopImageStream();

    print("[CAMERA] stream stopped");
  }

  /// DISPOSE CAMERA
  void dispose() {
    controller?.dispose();

    controller = null;

    _initialized = false;
  }
}
