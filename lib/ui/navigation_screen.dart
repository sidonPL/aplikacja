// lib/ui/navigation_screen.dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../models/location.dart';
import '../models/poi.dart';
import '../models/waypoint.dart';
import '../services/navigation_display_service.dart';
import '../services/route_calculator.dart';
import '../services/location_engine.dart';
import '../data/poi_repository.dart';

class NavigationScreen extends StatefulWidget {
  final Poi destination;

  const NavigationScreen({
    Key? key,
    required this.destination,
  }) : super(key: key);

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final LocationEngine _locationEngine = LocationEngine();
  final RouteCalculator _routeCalculator = RouteCalculator();
  late final NavigationDisplayService _navigationService;
  late final StreamSubscription _navigationSubscription;

  NavigationRoute? _route;
  int _currentSegmentIndex = 0;
  String _currentInstruction = "Ładowanie trasy...";
  double _distanceToNext = 0.0;
  double _distanceToDestination = 0.0;
  int _estimatedTimeSeconds = 0;
  Location? _currentLocation;
  bool _isNavigating = false;
  bool _hasReachedDestination = false;

  // Parametry mapy
  double _scale = 100; // piksele na metr

  @override
  void initState() {
    super.initState();
    _navigationService = NavigationDisplayService(
      locationEngine: _locationEngine,
      routeCalculator: _routeCalculator,
      poiRepository: PoiRepository(),
    );

    _navigationSubscription = _navigationService.navigationUpdates.listen(_handleNavigationUpdate);
    _startNavigation();
  }

  @override
  void dispose() {
    _navigationSubscription.cancel();
    _navigationService.dispose();
    super.dispose();
  }

  Future<void> _startNavigation() async {
    final success = await _navigationService.startNavigation(widget.destination.id);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się wyznaczyć trasy. Spróbuj ponownie.'),
            backgroundColor: Colors.red,
          )
      );
      Navigator.pop(context);
    }

    setState(() {
      _isNavigating = success;
    });
  }

  void _handleNavigationUpdate(NavigationUpdate update) {
    setState(() {
      switch (update.type) {
        case UpdateType.routeStarted:
          _route = update.route;
          _currentSegmentIndex = 0;
          _currentInstruction = update.route!.segments[0].instruction;
          _distanceToNext = update.distanceToNextWaypoint!;
          _distanceToDestination = update.route!.totalDistance;
          _estimatedTimeSeconds = update.route!.estimatedTimeSeconds;
          _isNavigating = true;
          break;

        case UpdateType.positionUpdate:
          _currentLocation = update.currentLocation;
          _distanceToNext = update.distanceToNextWaypoint!;
          _currentSegmentIndex = update.currentSegmentIndex!;

          if (_route != null) {
            _currentInstruction = _route!.segments[_currentSegmentIndex].instruction;

            // Oblicz pozostałą odległość do celu
            _distanceToDestination = 0;
            for (int i = _currentSegmentIndex; i < _route!.segments.length; i++) {
              _distanceToDestination += _route!.segments[i].connection.distance;
            }

            // Zaktualizuj szacowany czas
            _estimatedTimeSeconds = (_distanceToDestination / 1.2).round(); // 1.2 m/s - przeciętna prędkość chodu
          }
          break;

        case UpdateType.waypointReached:
          _currentSegmentIndex = update.currentSegmentIndex!;
          _currentInstruction = _route!.segments[_currentSegmentIndex].instruction;
          _distanceToNext = update.distanceToNextWaypoint!;

          // Powiadomienie dla użytkownika przy zmianie piętra
          final prevSegment = _route!.segments[_currentSegmentIndex - 1];
          final currentSegment = _route!.segments[_currentSegmentIndex];

          if (prevSegment.to.floor != currentSegment.from.floor) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Zmień piętro: ${prevSegment.to.floor} → ${currentSegment.from.floor}',
                    style: TextStyle(fontSize: 16),
                  ),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 5),
                )
            );
          }
          break;

        case UpdateType.destinationReached:
          _hasReachedDestination = true;
          _showDestinationReachedDialog();
          break;

        case UpdateType.navigationStopped:
          _isNavigating = false;
          break;

        case UpdateType.routeRecalculated:
          _route = update.route;
          _currentSegmentIndex = 0;
          _currentInstruction = update.route!.segments[0].instruction;
          _distanceToNext = update.distanceToNextWaypoint!;
          _distanceToDestination = update.route!.totalDistance;
          _estimatedTimeSeconds = update.route!.estimatedTimeSeconds;

          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Trasa została przeliczona'),
                backgroundColor: Colors.green,
              )
          );
          break;
      }
    });
  }

  void _showDestinationReachedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Cel osiągnięty!'),
        content: Text('Dotarłeś do punktu: ${widget.destination.name}'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Wróć do poprzedniego ekranu
            },
          ),
        ],
      ),
    );
  }

  void _recalculateRoute() {
    _navigationService.recalculateRoute();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Przeliczanie trasy...'))
    );
  }

  void _stopNavigation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Zakończ nawigację'),
        content: Text('Czy na pewno chcesz zakończyć nawigację?'),
        actions: [
          TextButton(
            child: Text('Anuluj'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: Text('Zakończ'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              _navigationService.stopNavigation();
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Wróć do poprzedniego ekranu
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Nawigacja do: ${widget.destination.name}'),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: _stopNavigation,
          tooltip: 'Zakończ nawigację',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _recalculateRoute,
            tooltip: 'Przelicz trasę',
          ),
        ],
      ),
      body: _isNavigating
          ? _buildNavigationView()
          : Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Wyznaczanie trasy do ${widget.destination.name}...'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationView() {
    if (_route == null) {
      return Center(child: Text('Ładowanie trasy...'));
    }

    return Column(
      children: [
        // Panel nawigacyjny na górze
        _buildNavigationPanel(),

        // Główny widok mapy
        Expanded(child: _buildMapView()),

        // Panel akcji na dole
        _buildActionsPanel(),
      ],
    );
  }

  Widget _buildNavigationPanel() {
    final remainingMinutes = (_estimatedTimeSeconds / 60).ceil();

    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Główna instrukcja
          Row(
            children: [
              Icon(Icons.navigation, size: 36, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentInstruction,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          SizedBox(height: 8),

          // Informacje o odległości i czasie
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Odległość do następnego punktu
              Row(
                children: [
                  Icon(Icons.arrow_forward, size: 18, color: Colors.blue.shade700),
                  SizedBox(width: 4),
                  Text(
                    'Następny punkt: ${_distanceToNext.toStringAsFixed(1)} m',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),

              // Odległość do celu
              Row(
                children: [
                  Icon(Icons.flag, size: 18, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Do celu: ${_distanceToDestination.toStringAsFixed(1)} m',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),

              // Szacowany czas
              Row(
                children: [
                  Icon(Icons.timer, size: 18, color: Colors.orange),
                  SizedBox(width: 4),
                  Text(
                    '$remainingMinutes min',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    if (_route == null) return Container();

    // Wymiary mapy
    double mapWidth = 800; // szerokość mapy w pikselach
    double mapHeight = 600; // wysokość mapy w pikselach

    // Pobierz wszystkie waypointy trasy
    final List<Waypoint> waypoints = _route!.waypoints;

    return InteractiveViewer(
      boundaryMargin: EdgeInsets.all(100),
      minScale: 0.5,
      maxScale: 4.0,
      child: Container(
        width: mapWidth,
        height: mapHeight,
        color: Colors.grey[100],
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(mapWidth, mapHeight),
            painter: _NavigationMapPainter(
              route: _route!,
              currentSegmentIndex: _currentSegmentIndex,
              currentLocation: _currentLocation,
              scale: _scale,
              destination: widget.destination,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsPanel() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Informacja o aktualnym piętrze
          Row(
            children: [
              Icon(Icons.layers, color: Colors.blue.shade700),
              SizedBox(width: 8),
              Text(
                'Piętro: ${_currentLocation?.floorId ?? 0}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),

          // Przyciski akcji
          Row(
            children: [
              // Przycisk do centrowania mapy
              IconButton(
                icon: Icon(Icons.my_location, color: Colors.blue.shade700),
                tooltip: 'Centruj na mojej pozycji',
                onPressed: () {
                  // Centrowanie widoku na aktualnej pozycji
                  // To byłoby zaimplementowane w faktycznym kontrolerze mapy
                },
              ),

              // Przycisk przełączania widoku 3D/2D
              IconButton(
                icon: Icon(Icons.view_in_ar, color: Colors.blue.shade700),
                tooltip: 'Przełącz widok 3D/2D',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Funkcja widoku 3D będzie dostępna wkrótce'),
                      )
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Klasa malująca mapę z trasą
class _NavigationMapPainter extends CustomPainter {
  final NavigationRoute route;
  final int currentSegmentIndex;
  final Location? currentLocation;
  final double scale;
  final Poi destination;

  static ui.Image? _staticLayerCache;
  static int? _cacheRouteHash;
  static int? _cacheSegmentIndex;
  static double? _cacheScale;
  static String? _cacheDestinationName;

  _NavigationMapPainter({
    required this.route,
    required this.currentSegmentIndex,
    this.currentLocation,
    required this.scale,
    required this.destination,
  });

  void _drawStaticLayer(Canvas canvas, Size size) {
    // Maluj tło mapy
    final backgroundPaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Malowanie przebytej części trasy
    final completedPathPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;
    if (currentSegmentIndex > 0) {
      final completedPath = Path();
      final firstPoint = route.waypoints[0];
      completedPath.moveTo(firstPoint.x * scale, firstPoint.y * scale);
      for (int i = 1; i <= currentSegmentIndex; i++) {
        final point = route.waypoints[i];
        completedPath.lineTo(point.x * scale, point.y * scale);
      }
      canvas.drawPath(completedPath, completedPathPaint);
    }

    // Malowanie pozostałej części trasy
    final remainingPathPaint = Paint()
      ..color = Colors.blue.shade300
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    if (currentSegmentIndex < route.segments.length) {
      final remainingPath = Path();
      final startPoint = route.waypoints[currentSegmentIndex];
      remainingPath.moveTo(startPoint.x * scale, startPoint.y * scale);
      for (int i = currentSegmentIndex + 1; i < route.waypoints.length; i++) {
        final point = route.waypoints[i];
        remainingPath.lineTo(point.x * scale, point.y * scale);
      }
      canvas.drawPath(remainingPath, remainingPathPaint);
    }

    // Punkty trasy
    final waypointPaint = Paint()..color = Colors.blue..style = PaintingStyle.fill;
    final currentWaypointPaint = Paint()..color = Colors.orange..style = PaintingStyle.fill;
    final destinationPaint = Paint()..color = Colors.red..style = PaintingStyle.fill;
    for (int i = 0; i < route.waypoints.length; i++) {
      final point = route.waypoints[i];
      final isCurrentPoint = i == currentSegmentIndex;
      final isDestination = i == route.waypoints.length - 1;
      final Paint pointPaint;
      double radius;
      if (isDestination) {
        pointPaint = destinationPaint;
        radius = 12.0;
      } else if (isCurrentPoint) {
        pointPaint = currentWaypointPaint;
        radius = 10.0;
      } else {
        pointPaint = waypointPaint;
        radius = 8.0;
      }
      canvas.drawCircle(Offset(point.x * scale, point.y * scale), radius, pointPaint);
      if (isCurrentPoint || isDestination) {
        final label = isDestination ? destination.name : "Punkt "+(i+1).toString();
        TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: Colors.black87,
              fontSize: isDestination ? 14 : 12,
              fontWeight: isDestination ? FontWeight.bold : FontWeight.normal,
              backgroundColor: Colors.white.withOpacity(0.7),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
            canvas,
            Offset(
                point.x * scale - (textPainter.width / 2),
                point.y * scale + radius + 4
            )
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final routeHash = route.hashCode;
    final segmentIndex = currentSegmentIndex;
    final scaleVal = scale;
    final destName = destination.name;
    bool cacheValid = _staticLayerCache != null &&
      _cacheRouteHash == routeHash &&
      _cacheSegmentIndex == segmentIndex &&
      _cacheScale == scaleVal &&
      _cacheDestinationName == destName;
    if (!cacheValid) {
      final recorder = ui.PictureRecorder();
      final staticCanvas = Canvas(recorder);
      _drawStaticLayer(staticCanvas, size);
      final picture = recorder.endRecording();
      picture.toImage(size.width.toInt(), size.height.toInt()).then((img) {
        _staticLayerCache = img;
        _cacheRouteHash = routeHash;
        _cacheSegmentIndex = segmentIndex;
        _cacheScale = scaleVal;
        _cacheDestinationName = destName;
        // Wymuś repaint po wygenerowaniu cache
      });
      // Rysuj warstwę statyczną tymczasowo bez cache
      _drawStaticLayer(canvas, size);
    } else {
      if (_staticLayerCache != null) {
        canvas.drawImage(_staticLayerCache!, Offset.zero, Paint());
      }
    }
    // Warstwa dynamiczna: pozycja użytkownika
    if (currentLocation != null) {
      final currentPosPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(currentLocation!.x * scale, currentLocation!.y * scale),
        12.0,
        currentPosPaint,
      );
      final arrowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final cx = currentLocation!.x * scale;
      final cy = currentLocation!.y * scale;
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy - 15), arrowPaint);
      canvas.drawLine(Offset(cx, cy - 15), Offset(cx - 5, cy - 10), arrowPaint);
      canvas.drawLine(Offset(cx, cy - 15), Offset(cx + 5, cy - 10), arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NavigationMapPainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.currentSegmentIndex != currentSegmentIndex ||
        oldDelegate.currentLocation?.x != currentLocation?.x ||
        oldDelegate.currentLocation?.y != currentLocation?.y ||
        oldDelegate.currentLocation?.floorId != currentLocation?.floorId ||
        oldDelegate.scale != scale ||
        oldDelegate.destination != destination;
  }
}