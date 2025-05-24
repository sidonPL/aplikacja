// lib/services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';

/// Service to handle runtime permissions for BLE and sensors
class PermissionService {
  /// Check if all required permissions are granted
  static Future<bool> hasAllPermissions() async {
    final statusLoc = await Permission.locationWhenInUse.status;
    final statusScan = await Permission.bluetoothScan.status;
    final statusConn = await Permission.bluetoothConnect.status;
    final statusAct = await Permission.activityRecognition.status;
    return statusLoc.isGranted && statusScan.isGranted && statusConn.isGranted && statusAct.isGranted;
  }

  /// Request all required permissions
  static Future<bool> requestAll() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.activityRecognition,
    ].request();
    return statuses.values.every((status) => status.isGranted);
  }
}

/// Convenience top-level function to request permissions
Future<bool> requestPermissions() async {
  return await PermissionService.requestAll();
}
