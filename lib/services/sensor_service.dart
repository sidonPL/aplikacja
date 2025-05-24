import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pedometer/pedometer.dart';

class SensorService {
  /// Kompas (kąt w stopniach 0-360)
  Stream<double> get heading$ =>
      FlutterCompass.events! .map((e) => e.heading ?? 0);

  /// Liczba kroków
  Stream<int> get stepCount$ =>
      Pedometer.stepCountStream .map((e) => e.steps);

  /// Surowe dane z akcelerometru
  Stream<AccelerometerEvent> get accelerometer$ =>
      accelerometerEventStream();

  /// Surowe dane z żyroskopu
  Stream<GyroscopeEvent> get gyroscope$ =>
      gyroscopeEventStream();
}