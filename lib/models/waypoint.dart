class Waypoint {
  final String id;
  final double x;
  final double y;
  final String label;
  final int? floor; // Dodajemy informację o piętrze

  Waypoint({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    this.floor
  });

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    label: json['label'] as String,
    floor: json['floor'] as int?,
  );
}