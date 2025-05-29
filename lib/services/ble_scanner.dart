import 'dart:developer' as developer;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/beacon.dart';

class BleScanner {
  /// Rozpocznij skanowanie BLE (opcjonalnie z limitem czasu)
  void startScan({Duration timeout = const Duration(seconds: 5)}) {
    developer.log('BleScanner: Rozpoczynanie skanowania...');
    FlutterBluePlus.startScan(timeout: timeout);
  }

  /// Zatrzymaj skanowanie
  void stopScan() {
    developer.log('BleScanner: Zatrzymywanie skanowania...');
    FlutterBluePlus.stopScan();
  }

  /// Strumień wyników skanowania, przemapowany na modele Beacon z nazwą i UUID
  Stream<List<Beacon>> get scanResults =>
      FlutterBluePlus.scanResults.map((results) {
        final beacons = results.map((r) {
          final advName = r.advertisementData.advName;
          final name = (advName.isNotEmpty)
              ? advName
              : r.device.remoteId.toString();
          
          return Beacon(
            uuid: r.device.remoteId.toString(),
            name: name,
            x: 0, // Te wartości powinny być pobrane z bazy danych
            y: 0, // na podstawie UUID
            rssi: r.rssi,
            floorId: 0, // Domyślne piętro, powinno być pobrane z bazy
          );
        }).toList();
        
        if (beacons.isNotEmpty) {
          developer.log('BleScanner: Znaleziono ${beacons.length} beaconów');
        }
        
        return beacons;
      });
}