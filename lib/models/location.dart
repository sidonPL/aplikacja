// lib/models/location.dart
class Location {
  final double x;
  final double y;
  final int floorId;

  Location({
    required this.x,
    required this.y,
    this.floorId = 0
  });

  Location copyWith({double? x, double? y, int? floorId}) {
    return Location(
      x: x ?? this.x,
      y: y ?? this.y,
      floorId: floorId ?? this.floorId,
    );
  }
}