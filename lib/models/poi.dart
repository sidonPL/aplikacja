// lib/models/poi.dart
class Poi {
  final String id;
  final String name;
  final String? description;
  final String type;
  final double x;
  final double y;
  final int floorId;
  final String? imagePath;
  final List<String> equipment;
  final int? capacity;

  Poi({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.x,
    required this.y,
    required this.floorId,
    this.imagePath,
    this.equipment = const [],
    this.capacity,
  });

  factory Poi.fromJson(Map<String, dynamic> json) {
    return Poi(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      type: json['type'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      floorId: json['floorId'] as int,
      imagePath: json['imagePath'] as String?,
      equipment: json['equipment'] != null
          ? List<String>.from(json['equipment'])
          : const [],
      capacity: json['capacity'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type,
      'x': x,
      'y': y,
      'floorId': floorId,
      'imagePath': imagePath,
      'equipment': equipment,
      'capacity': capacity,
    };
  }
}