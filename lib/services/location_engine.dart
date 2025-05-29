import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

import '../models/location.dart';
import '../models/beacon.dart';
import '../services/ble_scanner.dart';
import '../services/sensor_service.dart';
import '../utils/kalman_filter.dart';
import '../config/localization_method_enum.dart';

class LocationEngine {
  final BleScanner _ble = BleScanner();
  final SensorService _sensors = SensorService();
  final KalmanFilter _kfX = KalmanFilter();
  final KalmanFilter _kfY = KalmanFilter();

  LocalizationMethod method = LocalizationMethod.hybrid;
  Map<String, Map<String, int>>? _fingerprintDB;
  double _x = 0.0, _y = 0.0;
  int _currentFloorId = 0; // Dodane pole śledzące aktualne piętro
  StreamSubscription? _sensorSubscription;

  Stream<Location> get location$ async* {
    await _loadFingerprintDB();
    
    await for (final beacons in _ble.scanResults) {
      if (beacons.isEmpty) continue;

      developer.log('LocationEngine: Otrzymano ${beacons.length} beaconów');

      // Filtruj beacony tylko dla aktualnego piętra
      final floorBeacons = beacons.where((b) => b.floorId == _currentFloorId).toList();

      developer.log('LocationEngine: ${floorBeacons.length} beaconów na piętrze $_currentFloorId');

      // Jeśli nie ma wystarczającej liczby beaconów na tym piętrze, spróbuj określić piętro
      if (floorBeacons.length < 3) {
        // Prosta heurystyka - wybierz piętro z najsilniejszymi sygnałami
        final floorSignalStrength = <int, int>{};
        for (final beacon in beacons) {
          floorSignalStrength[beacon.floorId] =
              (floorSignalStrength[beacon.floorId] ?? 0) + beacon.rssi + 100; // +100 aby uniknąć wartości ujemnych
        }

        if (floorSignalStrength.isNotEmpty) {
          final bestFloor = floorSignalStrength.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          developer.log('LocationEngine: Wykryto najsilniejszy sygnał na piętrze $bestFloor');

          // Zmień piętro jeśli wykryliśmy silniejsze sygnały z innego piętra
          if (bestFloor != _currentFloorId) {
            developer.log('LocationEngine: Zmiana piętra z $_currentFloorId na $bestFloor');
            _currentFloorId = bestFloor;
          }
        }
      }

      // Użyj wszystkich beaconów lub tylko tych z aktualnego piętra
      final beaconsToUse = floorBeacons.length >= 3 ? floorBeacons : 
          beacons.where((b) => b.floorId == _currentFloorId).toList();

      if (beaconsToUse.isEmpty) {
        developer.log('LocationEngine: Brak beaconów do użycia');
        continue;
      }

      developer.log('LocationEngine: Używam ${beaconsToUse.length} beaconów');

      Location position;

      try {
        switch (method) {
          case LocalizationMethod.rssiKalman:
            final avgX = beaconsToUse.map((b) => b.x).reduce((a, b) => a + b) / beaconsToUse.length;
            final avgY = beaconsToUse.map((b) => b.y).reduce((a, b) => a + b) / beaconsToUse.length;
            position = Location(
              x: _kfX.estimate(avgX, avgX),
              y: _kfY.estimate(avgY, avgY),
              floorId: _currentFloorId,
            );
            break;

          case LocalizationMethod.trilateration:
          case LocalizationMethod.multilateration:
            position = _trilaterate(beaconsToUse);
            break;

          case LocalizationMethod.fingerprinting:
            position = _matchFingerprint(beaconsToUse);
            break;

          case LocalizationMethod.deadReckoning:
            position = await _estimateWithSensors();
            break;

          case LocalizationMethod.hybrid:
            final trilaterated = _trilaterate(beaconsToUse);
            position = Location(
              x: _kfX.estimate(trilaterated.x, trilaterated.x),
              y: _kfY.estimate(trilaterated.y, trilaterated.y),
              floorId: _currentFloorId,
            );
            break;
        }

        developer.log('LocationEngine: Pozycja: x=${position.x.toStringAsFixed(2)}, y=${position.y.toStringAsFixed(2)}, floor=${position.floorId}');
        yield position;
      } catch (e) {
        developer.log('LocationEngine: Błąd podczas obliczania pozycji: $e');
        // Zwróć poprzednią pozycję lub domyślną
        yield Location(x: _x, y: _y, floorId: _currentFloorId);
      }
    }
  }

  // Dodanie metody ustawiającej piętro
  void setFloor(int floorId) {
    developer.log('LocationEngine: Ustawienie piętra na $floorId');
    _currentFloorId = floorId;
    // Resetowanie kalmanów przy zmianie piętra
    _kfX.reset();
    _kfY.reset();
  }

  Location _trilaterate(List<Beacon> beacons) {
    if (beacons.length < 3) {
      developer.log('LocationEngine: Za mało beaconów do trilateracji (${beacons.length})');
      return Location(x: _x, y: _y, floorId: _currentFloorId);
    }

    try {
      final equations = <List<double>>[];
      final rhs = <double>[];

      final ref = beacons[0];
      final d1 = _rssiToDistance(ref.rssi);
      final x1 = ref.x;
      final y1 = ref.y;

      for (int i = 1; i < min(beacons.length, 4); i++) { // Użyj maksymalnie 4 beaconów
        final b = beacons[i];
        final di = _rssiToDistance(b.rssi);

        final A = 2 * (b.x - x1);
        final B = 2 * (b.y - y1);
        final C = pow(d1, 2) - pow(di, 2) - pow(x1, 2) + pow(b.x, 2) - pow(y1, 2) + pow(b.y, 2);

        equations.add([A, B]);
        rhs.add(C.toDouble());
      }

      if (equations.length < 2) {
        developer.log('LocationEngine: Za mało równań do rozwiązania');
        return Location(x: _x, y: _y, floorId: _currentFloorId);
      }

      final A = equations;
      final b = rhs;

      final At = _transpose(A);
      final AtA = _multiply(At, A);
      final Atb = _multiplyVector(At, b);
      final solution = _solveLinear(AtA, Atb);

      // Sprawdź czy rozwiązanie jest rozsądne
      if (solution[0].isNaN || solution[1].isNaN || 
          solution[0].isInfinite || solution[1].isInfinite) {
        developer.log('LocationEngine: Nieprawidłowe rozwiązanie trilateracji');
        return Location(x: _x, y: _y, floorId: _currentFloorId);
      }

      // Aktualizuj wewnętrzne współrzędne
      _x = solution[0];
      _y = solution[1];

      return Location(x: solution[0], y: solution[1], floorId: _currentFloorId);
    } catch (e) {
      developer.log('LocationEngine: Błąd trilateracji: $e');
      return Location(x: _x, y: _y, floorId: _currentFloorId);
    }
  }

  List<List<double>> _transpose(List<List<double>> matrix) {
    final rows = matrix.length;
    final cols = matrix[0].length;
    final transposed = List.generate(cols, (_) => List.filled(rows, 0.0));
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        transposed[j][i] = matrix[i][j];
      }
    }
    return transposed;
  }

  List<List<double>> _multiply(List<List<double>> a, List<List<double>> b) {
    final result = List.generate(a.length, (_) => List.filled(b[0].length, 0.0));
    for (int i = 0; i < a.length; i++) {
      for (int j = 0; j < b[0].length; j++) {
        for (int k = 0; k < b.length; k++) {
          result[i][j] += a[i][k] * b[k][j];
        }
      }
    }
    return result;
  }

  List<double> _multiplyVector(List<List<double>> a, List<double> v) {
    final result = List.filled(a.length, 0.0);
    for (int i = 0; i < a.length; i++) {
      for (int j = 0; j < v.length; j++) {
        result[i] += a[i][j] * v[j];
      }
    }
    return result;
  }

  List<double> _solveLinear(List<List<double>> a, List<double> b) {
    if (a.length != 2 || a[0].length != 2) {
      throw Exception('Tylko macierze 2x2 są obsługiwane');
    }
    
    final det = a[0][0] * a[1][1] - a[0][1] * a[1][0];
    if (det.abs() < 1e-10) {
      throw Exception('Macierz jest osobliwa');
    }
    
    final inv = [
      [a[1][1] / det, -a[0][1] / det],
      [-a[1][0] / det, a[0][0] / det]
    ];
    return [
      inv[0][0] * b[0] + inv[0][1] * b[1],
      inv[1][0] * b[0] + inv[1][1] * b[1],
    ];
  }

  double _rssiToDistance(int rssi, {int txPower = -59}) {
    if (rssi == 0) return -1.0;
    
    final double ratio = rssi * 1.0 / txPower;
    if (ratio < 1.0) {
      return pow(ratio, 10).toDouble();
    } else {
      final double accuracy = (0.89976) * pow(ratio, 7.7095) + 0.111;
      return accuracy;
    }
  }

  Future<void> _loadFingerprintDB() async {
    if (_fingerprintDB != null) return;
    try {
      final jsonString = await rootBundle.loadString('assets/data/fingerprints.json');
      final data = json.decode(jsonString) as Map<String, dynamic>;
      _fingerprintDB = data.map((point, beacons) => MapEntry(point, Map<String, int>.from(beacons)));
      developer.log('LocationEngine: Załadowano bazę fingerprints z ${_fingerprintDB!.length} punktami');
    } catch (e) {
      developer.log('LocationEngine: Błąd ładowania fingerprints: $e');
      _fingerprintDB = {};
    }
  }

  Location _matchFingerprint(List<Beacon> beacons) {
    if (_fingerprintDB == null || _fingerprintDB!.isEmpty) {
      developer.log('LocationEngine: Brak bazy fingerprints');
      return Location(x: _x, y: _y, floorId: _currentFloorId);
    }

    final inputVector = {for (var b in beacons) b.uuid: b.rssi};
    double minDist = double.infinity;
    String? bestPoint;

    _fingerprintDB!.forEach((point, fingerprint) {
      final dist = _euclideanDistance(fingerprint, inputVector);
      if (dist < minDist) {
        minDist = dist;
        bestPoint = point;
      }
    });

    if (bestPoint != null) {
      final coords = bestPoint!.split(',');
      // Zakładamy format "x,y,floorId" w kluczu punktów referencyjnych
      final floorId = coords.length > 2 ? int.tryParse(coords[2]) ?? _currentFloorId : _currentFloorId;
      
      _x = double.parse(coords[0]);
      _y = double.parse(coords[1]);
      
      return Location(
          x: _x,
          y: _y,
          floorId: floorId
      );
    }
    return Location(x: _x, y: _y, floorId: _currentFloorId);
  }

  double _euclideanDistance(Map<String, int> a, Map<String, int> b) {
    final keys = {...a.keys, ...b.keys};
    return sqrt(keys.map((k) => pow((a[k] ?? -100) - (b[k] ?? -100), 2)).reduce((v1, v2) => v1 + v2));
  }

  Future<Location> _estimateWithSensors() async {
    double angle = 0;
    double distance = 0;

    try {
      await for (final heading in _sensors.heading$) {
        angle = heading;
        break;
      }

      await for (final steps in _sensors.stepCount$) {
        distance = steps.toDouble();
        break;
      }

      final dx = distance * cos(angle * pi / 180);
      final dy = distance * sin(angle * pi / 180);

      _x += dx;
      _y += dy;
    } catch (e) {
      developer.log('LocationEngine: Błąd sensora: $e');
    }

    return Location(x: _x, y: _y, floorId: _currentFloorId);
  }

  void resetPosition() {
    developer.log('LocationEngine: Reset pozycji');
    _x = 0.0;
    _y = 0.0;
    // Zachowujemy _currentFloorId, żeby nie resetować piętra
    _kfX.reset();
    _kfY.reset();
  }

  void dispose() {
    _sensorSubscription?.cancel();
  }
}