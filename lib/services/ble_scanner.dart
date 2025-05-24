import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/beacon.dart';

class BleScanner {
  /// Rozpocznij skanowanie BLE (opcjonalnie z limitem czasu)
  void startScan({Duration timeout = const Duration(seconds: 5)}) {
    FlutterBluePlus.startScan(timeout: timeout);
  }

  /// Zatrzymaj skanowanie
  void stopScan() {
    FlutterBluePlus.stopScan();
  }

  /// Strumień wyników skanowania, przemapowany na modele Beacon z nazwą i UUID
  Stream<List<Beacon>> get scanResults =>
      FlutterBluePlus.scanResults.map((results) =>
          results.map((r) {
            final advName = r.advertisementData.advName;
            final name = (advName.isNotEmpty)
                ? advName
                : r.device.remoteId;
            return Beacon(
              uuid: r.device.remoteId.toString() ,
              name: name.toString(),
              x: 0,
              y: 0,
              rssi: r.rssi,
            );
          }).toList());
}
