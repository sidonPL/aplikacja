// lib/services/navigation_display_service.dart
import 'dart:async';
import 'dart:math';
import '../models/location.dart';
import '../models/poi.dart';
import 'location_engine.dart';
import 'route_calculator.dart';
import '../data/poi_repository.dart';

class NavigationDisplayService {
  final LocationEngine _locationEngine;
  final RouteCalculator _routeCalculator;
  final PoiRepository _poiRepository;

  StreamSubscription? _locationSubscription;
  NavigationRoute? _currentRoute;
  int _currentSegmentIndex = 0;
  bool _isNavigating = false;

  final _navigationController = StreamController<NavigationUpdate>.broadcast();
  Stream<NavigationUpdate> get navigationUpdates => _navigationController.stream;

  NavigationDisplayService({
    required LocationEngine locationEngine,
    required RouteCalculator routeCalculator,
    required PoiRepository poiRepository,
  }) :
        _locationEngine = locationEngine,
        _routeCalculator = routeCalculator,
        _poiRepository = poiRepository;

  Future<bool> startNavigation(String destinationId) async {
    // Znajdź POI
    final allPois = await _poiRepository.getPois();
    final destination = allPois.firstWhere(
            (poi) => poi.id == destinationId,
        orElse: () => throw Exception('Nie znaleziono punktu docelowego')
    );

    // Pobierz aktualną lokalizację
    Location? userLocation;
    await for (final location in _locationEngine.location$) {
      userLocation = location;
      break;  // Pobierz tylko pierwszą lokalizację
    }

    if (userLocation == null) {
      return false;
    }

    // Oblicz trasę
    final route = await _routeCalculator.calculateRoute(
        userLocation,
        destination.id
    );

    if (route == null) {
      return false;
    }

    _currentRoute = route;
    _currentSegmentIndex = 0;
    _isNavigating = true;

    // Powiadom o rozpoczęciu nawigacji
    _navigationController.add(NavigationUpdate(
      type: UpdateType.routeStarted,
      route: route,
      destination: destination,
      currentSegmentIndex: 0,
      distanceToNextWaypoint: route.segments[0].connection.distance, // Zmieniono weight na distance
    ));

    // Rozpocznij nawigację
    _startLocationUpdates();

    return true;
  }

  void _startLocationUpdates() {
    _locationSubscription?.cancel();
    _locationSubscription = _locationEngine.location$.listen((location) {
      if (!_isNavigating || _currentRoute == null) return;

      // Sprawdź, czy dotarliśmy do kolejnego punktu
      final currentSegment = _currentRoute!.segments[_currentSegmentIndex];
      final nextWaypoint = currentSegment.to;

      final distance = _calculateDistance(
          location.x, location.y,
          nextWaypoint.x, nextWaypoint.y
      );

      // Odległość, przy której uznajemy punkt za osiągnięty
      final waypointReachedThreshold = 2.0; // metry

      if (distance < waypointReachedThreshold) {
        _currentSegmentIndex++;

        // Sprawdź czy dotarliśmy do celu
        if (_currentSegmentIndex >= _currentRoute!.segments.length) {
          _navigationController.add(NavigationUpdate(
            type: UpdateType.destinationReached,
            route: _currentRoute!,
            currentSegmentIndex: _currentSegmentIndex - 1,
            distanceToNextWaypoint: 0,
          ));

          stopNavigation();
          return;
        }

        // Powiadom o dotarciu do punktu pośredniego
        _navigationController.add(NavigationUpdate(
          type: UpdateType.waypointReached,
          route: _currentRoute!,
          currentSegmentIndex: _currentSegmentIndex,
          distanceToNextWaypoint: _currentRoute!.segments[_currentSegmentIndex].connection.distance, // Zmieniono weight na distance
        ));
      } else {
        // Aktualizacja pozycji
        _navigationController.add(NavigationUpdate(
          type: UpdateType.positionUpdate,
          route: _currentRoute!,
          currentSegmentIndex: _currentSegmentIndex,
          distanceToNextWaypoint: distance,
          currentLocation: location,
        ));
      }
    });
  }

  void stopNavigation() {
    _locationSubscription?.cancel();
    _isNavigating = false;
    _currentRoute = null;
    _currentSegmentIndex = 0;

    _navigationController.add(NavigationUpdate(
      type: UpdateType.navigationStopped,
    ));
  }

  void recalculateRoute() async {
    if (!_isNavigating || _currentRoute == null) return;

    Location? userLocation;
    await for (final location in _locationEngine.location$) {
      userLocation = location;
      break;
    }

    if (userLocation == null) return;

    // Znajdź cel obecnej trasy
    final destinationWaypointId = _currentRoute!.waypoints.last.id;

    // Oblicz nową trasę
    final newRoute = await _routeCalculator.calculateRoute(
        userLocation,
        destinationWaypointId
    );

    if (newRoute == null) return;

    _currentRoute = newRoute;
    _currentSegmentIndex = 0;

    _navigationController.add(NavigationUpdate(
      type: UpdateType.routeRecalculated,
      route: newRoute,
      currentSegmentIndex: 0,
      distanceToNextWaypoint: newRoute.segments[0].connection.distance, // Zmieniono weight na distance
      currentLocation: userLocation,
    ));
  }

  double getEstimatedTimeRemaining() {
    if (!_isNavigating || _currentRoute == null) return 0;

    double remainingDistance = 0;
    for (int i = _currentSegmentIndex; i < _currentRoute!.segments.length; i++) {
      remainingDistance += _currentRoute!.segments[i].connection.distance; // Zmieniono weight na distance
    }

    // Szacowany czas w sekundach
    final averageWalkingSpeed = 1.2; // metry/sekundę
    return remainingDistance / averageWalkingSpeed;
  }

  double _calculateDistance(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  }

  void dispose() {
    _locationSubscription?.cancel();
    _navigationController.close();
  }
}

enum UpdateType {
  routeStarted,
  positionUpdate,
  waypointReached,
  destinationReached,
  navigationStopped,
  routeRecalculated
}

class NavigationUpdate {
  final UpdateType type;
  final NavigationRoute? route;
  final Poi? destination;
  final int? currentSegmentIndex;
  final double? distanceToNextWaypoint;
  final Location? currentLocation;

  NavigationUpdate({
    required this.type,
    this.route,
    this.destination,
    this.currentSegmentIndex,
    this.distanceToNextWaypoint,
    this.currentLocation,
  });
}