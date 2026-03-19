// lib/core/permissions.dart

import 'package:permission_handler/permission_handler.dart';

class AppPermissions {

  static Future<bool> requestCamera() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  static Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }
}