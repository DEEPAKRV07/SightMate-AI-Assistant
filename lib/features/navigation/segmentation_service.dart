import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

class SegmentationService {
  Interpreter? _interpreter;
  bool _loaded = false;

  static const int inputSize = 257;

  Future<void> loadModel() async {
    if (_loaded) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/deeplabv3.tflite',
      options: InterpreterOptions()..threads = 4,
    );

    print("[SEG] Model loaded");

    print("[SEG] Input shape: ${_interpreter!.getInputTensor(0).shape}");
    print("[SEG] Output shape: ${_interpreter!.getOutputTensor(0).shape}");

    _loaded = true;
  }

  Future<List<List<int>>> runSegmentation(String imagePath) async {
    if (_interpreter == null) return [];

    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) return [];

    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
    );

    /// INPUT
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final p = resized.getPixel(x, y);

            return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
          },
        ),
      ),
    );

    /// READ OUTPUT SHAPE
    final outputShape = _interpreter!.getOutputTensor(0).shape;

    int h = outputShape[1];
    int w = outputShape[2];
    int classes = outputShape[3];

    print("[SEG] output tensor: $outputShape");

    /// OUTPUT BUFFER
    var output = List.generate(
      1,
      (_) => List.generate(
        h,
        (_) => List.generate(
          w,
          (_) => List.filled(classes, 0.0),
        ),
      ),
    );

    _interpreter!.run(input, output);

    /// Convert to mask
    List<List<int>> mask = List.generate(
      h,
      (_) => List.filled(w, 0),
    );

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double maxScore = 0;
        int classIndex = 0;

        for (int c = 0; c < classes; c++) {
          double score = output[0][y][x][c];

          if (score > maxScore) {
            maxScore = score;
            classIndex = c;
          }
        }

        mask[y][x] = classIndex;
      }
    }

    return mask;
  }

  Map<String, double> analyzeWalkable(List<List<int>> mask) {
    if (mask.isEmpty) {
      return {"left": 0, "center": 0, "right": 0};
    }

    int h = mask.length;
    int w = mask[0].length;

    double leftObstacle = 0;
    double centerObstacle = 0;
    double rightObstacle = 0;

    /// obstacle classes (VOC dataset approx)
    const obstacleClasses = {
      15, // person
      9, // chair
      10, // sofa
      11, // table
      20, // tv/monitor
    };

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int label = mask[y][x];

        if (!obstacleClasses.contains(label)) continue;

        if (x < w * 0.33) {
          leftObstacle++;
        } else if (x < w * 0.66) {
          centerObstacle++;
        } else {
          rightObstacle++;
        }
      }
    }

    double totalPixels = (h * w).toDouble();

    return {
      "left": leftObstacle / totalPixels,
      "center": centerObstacle / totalPixels,
      "right": rightObstacle / totalPixels
    };
  }
}
