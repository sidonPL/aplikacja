// lib/services/route_calculator.dart
import '../models/waypoint.dart';
import '../models/connection.dart';
import '../models/location.dart';
import '../data/graph_repository.dart';
import 'dart:math';

class PathSegment {
  final Waypoint from;
  final Waypoint to;
  final Connection connection;
  final String instruction;

  PathSegment({
    required this.from,
    required this.to,
    required this.connection,
    required this.instruction
  });
}

class NavigationRoute {
  final List<Waypoint> waypoints;
  final List<PathSegment> segments;
  final double totalDistance;
  final int estimatedTimeSeconds;

  NavigationRoute({
    required this.waypoints,
    required this.segments,
    required this.totalDistance,
    required this.estimatedTimeSeconds
  });
}

class RouteCalculator {
  final GraphRepository _graphRepository = GraphRepository();
  final double _averageWalkingSpeed = 1.2; // metry/sekundę

  // Znajdź najbliższy punkt nawigacyjny
  Future<Waypoint?> findClosestWaypoint(Location userLocation) async {
    final waypoints = await _graphRepository.getWaypoints();

    // Filtrujemy punkty z tego samego piętra co użytkownik
    final floorWaypoints = waypoints.where((w) => w.floor == userLocation.floorId).toList();

    if (floorWaypoints.isEmpty) return null;

    Waypoint? closest;
    double minDistance = double.infinity;

    for (var waypoint in floorWaypoints) {
      final distance = _calculateDistance(
          userLocation.x, userLocation.y,
          waypoint.x, waypoint.y
      );

      if (distance < minDistance) {
        minDistance = distance;
        closest = waypoint;
      }
    }

    return closest;
  }

  // Algorytm A* do wyznaczania najkrótszej ścieżki
  Future<NavigationRoute?> calculateRoute(Location start, String destinationId) async {
    // Znajdź najbliższy punkt nawigacyjny do użytkownika
    final startWaypoint = await findClosestWaypoint(start);
    if (startWaypoint == null) return null;

    final waypoints = await _graphRepository.getWaypoints();
    final connections = await _graphRepository.getConnections();

    // Sprawdź czy cel istnieje
    final destinationWaypoint = waypoints.firstWhere(
            (w) => w.id == destinationId,
        orElse: () => throw Exception('Punkt docelowy nie istnieje')
    );

    // Mapa połączeń dla szybszego dostępu
    final Map<String, List<Connection>> adjacencyMap = {};
    for (var connection in connections) {
      if (!adjacencyMap.containsKey(connection.from)) {
        adjacencyMap[connection.from] = [];
      }
      adjacencyMap[connection.from]!.add(connection);
    }

    // Mapa punktów nawigacyjnych według id
    final Map<String, Waypoint> waypointMap = {
      for (var waypoint in waypoints) waypoint.id: waypoint
    };

    // Implementacja algorytmu A*
    final openSet = <String>{startWaypoint.id};
    final closedSet = <String>{};

    // Koszt dojścia do danego punktu
    final gScore = <String, double>{startWaypoint.id: 0};

    // Szacowany całkowity koszt ścieżki przez ten punkt
    final fScore = <String, double>{
      startWaypoint.id: _heuristic(startWaypoint, destinationWaypoint)
    };

    // Poprzedniki na ścieżce
    final Map<String, String> cameFrom = {};

    // Użyte połączenia na ścieżce
    final Map<String, Connection> usedConnections = {};

    while (openSet.isNotEmpty) {
      // Wybierz punkt z najniższym fScore
      String current = openSet.reduce(
              (a, b) => (fScore[a] ?? double.infinity) < (fScore[b] ?? double.infinity) ? a : b
      );

      // Sprawdź czy dotarliśmy do celu
      if (current == destinationId) {
        return _reconstructPath(
            current,
            cameFrom,
            usedConnections,
            waypointMap
        );
      }

      openSet.remove(current);
      closedSet.add(current);

      // Sprawdź wszystkich sąsiadów
      for (var connection in adjacencyMap[current] ?? []) {
        final neighbor = connection.to;

        // Pomijamy już przetworzone punkty
        if (closedSet.contains(neighbor)) continue;

        final tentativeGScore = (gScore[current] ?? double.infinity) + connection.distance;

        // Sprawdź czy znaleziono lepszą ścieżkę
        if (!openSet.contains(neighbor)) {
          openSet.add(neighbor);
        } else if (tentativeGScore >= (gScore[neighbor] ?? double.infinity)) {
          continue;
        }

        // Ta ścieżka jest lepsza
        cameFrom[neighbor] = current;
        usedConnections[neighbor] = connection;
        gScore[neighbor] = tentativeGScore;
        fScore[neighbor] = tentativeGScore +
            _heuristic(waypointMap[neighbor]!, destinationWaypoint);
      }
    }

    return null; // Nie znaleziono ścieżki
  }

  // Funkcja heurystyczna - dystans euklidesowy
  double _heuristic(Waypoint a, Waypoint b) {
    // Jeżeli punkty są na różnych piętrach, dodajemy karę
    final floorPenalty = (a.floor != b.floor && a.floor != null && b.floor != null) ? 50.0 : 0.0;
    return _calculateDistance(a.x, a.y, b.x, b.y) + floorPenalty;
  }

  // Odtworzyć ścieżkę z punktu końcowego
  Future<NavigationRoute> _reconstructPath(
      String endId,
      Map<String, String> cameFrom,
      Map<String, Connection> usedConnections,
      Map<String, Waypoint> waypointMap
      ) async {
    var pathNodes = <String>[];
    var current = endId;

    while (cameFrom.containsKey(current)) {
      pathNodes.add(current);
      current = cameFrom[current]!;
    }
    pathNodes.add(current); // Dodaj punkt startowy
    pathNodes = pathNodes.reversed.toList();

    final waypoints = pathNodes.map((id) => waypointMap[id]!).toList();

    // Utwórz segmenty ścieżki z instrukcjami
    final segments = <PathSegment>[];
    double totalDistance = 0;

    for (int i = 0; i < pathNodes.length - 1; i++) {
      final fromId = pathNodes[i];
      final toId = pathNodes[i + 1];
      final fromWaypoint = waypointMap[fromId]!;
      final toWaypoint = waypointMap[toId]!;
      final connection = usedConnections[toId]!;

      final instruction = _generateInstruction(fromWaypoint, toWaypoint, connection);

      segments.add(PathSegment(
        from: fromWaypoint,
        to: toWaypoint,
        connection: connection,
        instruction: instruction,
      ));

      totalDistance += connection.distance;
    }

    // Oblicz szacowany czas podróży w sekundach
    final estimatedTime = (totalDistance / _averageWalkingSpeed).round();

    return NavigationRoute(
      waypoints: waypoints,
      segments: segments,
      totalDistance: totalDistance,
      estimatedTimeSeconds: estimatedTime,
    );
  }

  // Generuj instrukcje nawigacyjne
  String _generateInstruction(Waypoint from, Waypoint to, Connection connection) {
    // Oblicz kierunek
    final dx = to.x - from.x;
    final dy = to.y - from.y;

    // Zmiana piętra
    if (from.floor != to.floor && from.floor != null && to.floor != null) {
      if (to.floor! > from.floor!) {
        return "Idź na wyższe piętro (${from.floor} → ${to.floor})";
      } else {
        return "Idź na niższe piętro (${from.floor} → ${to.floor})";
      }
    }

    // Określ kierunek w płaszczyźnie poziomej
    final angle = (atan2(dy, dx) * 180 / pi + 360) % 360;
    final direction = _getDirectionFromAngle(angle);

    // Sprawdź typ połączenia
    final connectionType = connection.type;

    // Można też użyć etykiety waypointu do lepszych instrukcji
    if (to.label.toLowerCase().contains("schody") ||
        to.label.toLowerCase().contains("stairs")) {
      return "Idź ${direction.toLowerCase()} do schodów";
    } else if (to.label.toLowerCase().contains("winda") ||
        to.label.toLowerCase().contains("elevator")) {
      return "Idź ${direction.toLowerCase()} do windy";
    } else if (connectionType == "door" ||
        to.label.toLowerCase().contains("drzwi") ||
        to.label.toLowerCase().contains("door")) {
      return "Idź ${direction.toLowerCase()} przez drzwi";
    } else {
      return "Idź ${direction.toLowerCase()} ${connection.distance.toStringAsFixed(1)}m do ${to.label}";
    }
  }

  // Konwersja kąta na kierunek
  String _getDirectionFromAngle(double angle) {
    if (angle >= 337.5 || angle < 22.5) return "na wschód";
    if (angle >= 22.5 && angle < 67.5) return "na północny wschód";
    if (angle >= 67.5 && angle < 112.5) return "na północ";
    if (angle >= 112.5 && angle < 157.5) return "na północny zachód";
    if (angle >= 157.5 && angle < 202.5) return "na zachód";
    if (angle >= 202.5 && angle < 247.5) return "na południowy zachód";
    if (angle >= 247.5 && angle < 292.5) return "na południe";
    return "na południowy wschód";
  }

  // Oblicz odległość euklidesową
  double _calculateDistance(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  }
}