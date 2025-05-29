import '../models/poi.dart';
import '../models/waypoint.dart';
import 'local_storage_service.dart';
import 'dart:math';

class PoiRepository {
  final LocalStorageService _storage = LocalStorageService();

  Future<List<Poi>> getPois() => _storage.loadPois();

  /// Znajdź waypoint powiązany z POI
  Future<Waypoint?> getWaypointForPoi(String poiId) async {
    final pois = await getPois();
    final waypoints = await _storage.loadWaypoints();

    final poi = pois.firstWhere(
          (p) => p.id == poiId,
      orElse: () => throw Exception('POI nie istnieje: $poiId'),
    );

    // Znajdź najbliższy waypoint na tym samym piętrze
    final floorWaypoints = waypoints.where(
            (w) => w.floor == poi.floorId
    ).toList();

    if (floorWaypoints.isEmpty) return null;

    Waypoint? closest;
    double minDistance = double.infinity;

    for (var waypoint in floorWaypoints) {
      final distance = _calculateDistance(
          poi.x, poi.y,
          waypoint.x, waypoint.y
      );

      if (distance < minDistance) {
        minDistance = distance;
        closest = waypoint;
      }
    }

    return closest;
  }

  double _calculateDistance(double x1, double y1, double x2, double y2) {
    return sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  }
}