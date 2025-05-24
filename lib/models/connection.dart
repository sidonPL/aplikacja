class Connection {
  final String from;
  final String to;
  final double distance;
  final String? type; // Dodajemy informację o typie połączenia

  Connection({
    required this.from,
    required this.to,
    required this.distance,
    this.type
  });

  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
    from: json['from'] as String,
    to: json['to'] as String,
    distance: (json['distance'] as num).toDouble(),
    type: json['type'] as String?,
  );
}