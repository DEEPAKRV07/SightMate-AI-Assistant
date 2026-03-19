import '../object_detection/yolo_service.dart';

class NavigationFusionService {
  String decideNavigation(
    List<DetectionResult> detections,
    double segCenter,
    double segLeft,
    double segRight,
  ) {
    double leftDanger = segLeft;
    double centerDanger = segCenter;
    double rightDanger = segRight;

    String objectName = "";

    for (var d in detections) {
      double x = d.rect.center.dx;

      double danger = (d.rect.height * d.rect.height) * d.confidence;

      if (d.rect.height < 0.10) continue;

      if (x < 0.33) {
        leftDanger += danger;
      } else if (x < 0.66) {
        centerDanger += danger;
        objectName = d.label;
      } else {
        rightDanger += danger;
      }
    }

    print("[NAV] YOLO L:$leftDanger C:$centerDanger R:$rightDanger");
    print("[NAV] SEG  L:$segLeft C:$segCenter R:$segRight");

    /// MAIN OBSTACLE
    if (centerDanger > 0.30) {
      if (leftDanger < rightDanger && leftDanger < 0.20) {
        return "Move left. $objectName ahead";
      }

      if (rightDanger < leftDanger && rightDanger < 0.20) {
        return "Move right. $objectName ahead";
      }

      if (objectName.isNotEmpty) {
        return "$objectName ahead";
      }

      return "Obstacle ahead";
    }

    /// SIDE OBSTACLES
    if (leftDanger > 0.35 && rightDanger < 0.20) {
      return "Move right";
    }

    if (rightDanger > 0.35 && leftDanger < 0.20) {
      return "Move left";
    }

    return "Path clear";
  }
}
