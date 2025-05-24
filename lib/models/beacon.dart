// lib/models/beacon.dart
class Beacon {
  final String uuid;
  final String name;
  final int rssi;
  final double x;
  final double y;
  final int floorId;

  Beacon({
    required this.uuid,
    required this.name,
    this.rssi = -70,  // Domyślna wartość RSSI
    required this.x,
    required this.y,
    this.floorId = 0,
  });

  // Konstruktor fabryczny do konwersji z formatu JSON
  factory Beacon.fromJson(Map<String, dynamic> json) {
    return Beacon(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      rssi: json['rssi'] as int? ?? -70,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      floorId: json['floorId'] as int? ?? 0,
    );
  }

  // Metoda do konwersji instancji Beacon na format JSON
  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'rssi': rssi,
      'x': x,
      'y': y,
      'floorId': floorId,
    };
  }

  // Fabryka do tworzenia Beacon z danych BLE
  factory Beacon.fromScanResult(dynamic scanResult, {double x = 0, double y = 0, int floorId = 0}) {
    return Beacon(
        uuid: scanResult.id,
        name: scanResult.name ?? 'Unknown',
        rssi: scanResult.rssi,
        x: x,
        y: y,
        floorId: floorId
    );
  }

  // Metoda do tworzenia kopii obiektu z możliwością nadpisania wybranych pól
  Beacon copyWith({
    String? uuid,
    String? name,
    int? rssi,
    double? x,
    double? y,
    int? floorId,
  }) {
    return Beacon(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      x: x ?? this.x,
      y: y ?? this.y,
      floorId: floorId ?? this.floorId,
    );
  }
}