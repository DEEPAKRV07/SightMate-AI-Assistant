import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class DetectionResult {
  final String label;
  final Rect rect;
  final double confidence;

  DetectionResult({
    required this.label,
    required this.rect,
    required this.confidence,
  });
}

class YoloService {
  static final YoloService _instance =
  YoloService._internal();
  factory YoloService() => _instance;
  YoloService._internal();

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _loaded = false;

  static const int inputSize = 320;

  Future<void> loadModel() async {
    if (_loaded) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/yolov8n_320_int8.tflite',
      options: InterpreterOptions()..threads = 4,
    );

    final labelData =
    await rootBundle.loadString(
        'assets/models/labels.txt');

    _labels = labelData.split('\n');

    print("[YOLO] Labels: ${_labels.length}");
    _loaded = true;
  }

  Future<List<DetectionResult>> detectFromFile(
      String path) async {

    if (_interpreter == null) return [];

    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return [];

    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
    );

    final input = List.generate(
      1,
          (_) => List.generate(
        inputSize,
            (y) => List.generate(
          inputSize,
              (x) {
            final p =
            resized.getPixel(x, y);
            return [
              p.r / 255.0,
              p.g / 255.0,
              p.b / 255.0,
            ];
          },
        ),
      ),
    );

    final outputShape =
        _interpreter!
            .getOutputTensor(0)
            .shape;

    var output = List.generate(
      outputShape[0],
          (_) => List.generate(
        outputShape[1],
            (_) =>
            List.filled(
                outputShape[2], 0.0),
      ),
    );

    _interpreter!.run(input, output);

    int features = outputShape[1];
    int preds = outputShape[2];

    List<DetectionResult> results = [];

    for (int i = 0; i < preds; i++) {

      double maxScore = 0;
      int classIndex = -1;

      for (int j = 4; j < features; j++) {
        if (output[0][j][i] > maxScore) {
          maxScore = output[0][j][i];
          classIndex = j - 4;
        }
      }

      if (maxScore < 0.5) continue;
      if (classIndex < 0 ||
          classIndex >= _labels.length)
        continue;

      double x =
          output[0][0][i] * inputSize;
      double y =
          output[0][1][i] * inputSize;
      double w =
          output[0][2][i] * inputSize;
      double h =
          output[0][3][i] * inputSize;

      final rect = Rect.fromCenter(
        center: Offset(x / inputSize,
            y / inputSize),
        width: w / inputSize,
        height: h / inputSize,
      );

      results.add(
        DetectionResult(
          label: _labels[classIndex],
          rect: rect,
          confidence: maxScore,
        ),
      );
    }

    return _applyNMS(results);
  }

  List<DetectionResult> _applyNMS(
      List<DetectionResult> detections) {

    detections.sort(
            (a, b) =>
            b.confidence
                .compareTo(a.confidence));

    List<DetectionResult> finalList = [];

    for (var d in detections) {
      bool keep = true;

      for (var f in finalList) {
        if (_iou(d.rect, f.rect) > 0.5) {
          keep = false;
          break;
        }
      }

      if (keep) finalList.add(d);
    }

    return finalList;
  }

  double _iou(Rect a, Rect b) {
    final inter = a.intersect(b);
    if (inter.isEmpty) return 0;
    final area =
        inter.width * inter.height;
    final union =
        a.width * a.height +
            b.width * b.height -
            area;
    return area / union;
  }
}