// lib/models/floor.dart
class Floor {
  final int id;
  final String name;
  final double width;
  final double height;
  final String? imagePath;

  Floor({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.imagePath,
  });
}