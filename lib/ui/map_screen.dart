import 'dart:async';
import 'package:flutter/material.dart';
import '../config/localization_method_enum.dart';
import '../models/beacon.dart';
import '../models/location.dart';
import '../models/poi.dart';
import '../models/floor.dart';
import '../services/location_engine.dart';
import '../services/permission_service.dart';
import '../data/beacon_repository.dart';
import '../data/poi_repository.dart';
import '../services/ble_scanner.dart';
import '../ui/navigation_screen.dart';
import '../ui/search_screen.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final LocationEngine _locationEngine = LocationEngine();
  final BleScanner _bleScanner = BleScanner();
  final BeaconRepository _beaconRepository = BeaconRepository();
  final PoiRepository _poiRepository = PoiRepository();

  StreamSubscription? _locationSubscription;
  StreamSubscription? _bleSubscription;

  List<Beacon> _beacons = [];
  List<Poi> _pois = [];
  Location? _currentLocation;

  bool _isScanning = false;
  bool _hasPermissions = false;
  bool _isLocationEngineRunning = false;
  int _currentFloorId = 0;

  // Parametry mapy - zmniejszona początkowa skala
  double _scale = 10.0; // zmienione z 10.0 na 1.0
  Offset _mapOffset = Offset(0, 0);

  // Kontroler transformacji mapy
  final TransformationController _transformationController = TransformationController();

  // Lista pięter - zmienione na PNG
  final List<Floor> _floors = [
    Floor(id: 0, name: 'Parter', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_0.png'),
    Floor(id: 1, name: '1 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_1.png'),
    Floor(id: 2, name: '2 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_2.png'),
    Floor(id: 3, name: '3 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_3.png'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
    _checkPermissions();
    _loadBeacons();
    _loadPois();
    // Ustawienie początkowej transformacji po zbudowaniu widoku
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setInitialTransform();
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _bleSubscription?.cancel();
    _locationEngine.dispose();
    _transformationController.dispose();
    WidgetsBinding.instance?.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isScanning) _startScanning();
    } else if (state == AppLifecycleState.paused) {
      _bleScanner.stopScan();
    }
  }

  // Nowa metoda do ustawienia początkowej transformacji
  void _setInitialTransform() {
    final currentFloor = _floors.firstWhere(
          (floor) => floor.id == _currentFloorId,
      orElse: () => _floors.first,
    );

    final screenSize = MediaQuery.of(context).size;
    final mapWidth = currentFloor.width;
    final mapHeight = currentFloor.height;

    // Oblicz skalę, aby mapa zmieściła się na ekranie
    final scaleX = screenSize.width / mapWidth;
    final scaleY = (screenSize.height - 200) / mapHeight; // 200px dla paneli
    final optimalScale = (scaleX < scaleY ? scaleX : scaleY) * 0.9; // 90% dla marginesu

    setState(() {
      _scale = optimalScale;
    });

    // Wyśrodkuj mapę
    final matrix = Matrix4.identity()
      ..scale(optimalScale)
      ..translate(
        (screenSize.width - mapWidth * optimalScale) / (2 * optimalScale),
        (screenSize.height - mapHeight * optimalScale) / (2 * optimalScale),
      );

    _transformationController.value = matrix;
  }

  Future<void> _checkPermissions() async {
    final hasPermissions = await PermissionService.hasAllPermissions();
    setState(() {
      _hasPermissions = hasPermissions;
    });

    if (!hasPermissions) {
      final granted = await PermissionService.requestAll();
      setState(() {
        _hasPermissions = granted;
      });

      if (granted) {
        _startScanning();
        _startLocationEngine();
      }
    } else {
      _startScanning();
      _startLocationEngine();
    }
  }

  Future<void> _loadBeacons() async {
    final beacons = await _beaconRepository.getBeacons();
    setState(() {
      _beacons = beacons;
    });
  }

  Future<void> _loadPois() async {
    final pois = await _poiRepository.getPois();
    setState(() {
      _pois = pois;
    });
  }

  void _startScanning() {
    if (!_hasPermissions) return;

    setState(() {
      _isScanning = true;
    });

    _bleScanner.startScan();
    _bleSubscription?.cancel();
    _bleSubscription = _bleScanner.scanResults.listen((beacons) {
      setState(() {
        for (var beacon in beacons) {
          final index = _beacons.indexWhere((b) => b.uuid == beacon.uuid);
          if (index >= 0) {
            _beacons[index] = _beacons[index].copyWith(rssi: beacon.rssi);
          }
        }
      });
    });
  }

  void _startLocationEngine() {
    if (!_hasPermissions || _isLocationEngineRunning) return;

    setState(() {
      _isLocationEngineRunning = true;
    });

    _locationSubscription?.cancel();
    _locationSubscription = _locationEngine.location$.listen((location) {
      setState(() {
        _currentLocation = location;

        if (location.floorId != _currentFloorId) {
          _currentFloorId = location.floorId;
        }
      });
    });
  }

  void _resetLocation() {
    _locationEngine.resetPosition();
    setState(() {
      _currentLocation = null;
    });
  }

  void _changeLocalizationMethod(LocalizationMethod method) {
    _locationEngine.method = method;
    _resetLocation();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Metoda lokalizacji zmieniona na: ${method.toString().split('.').last}')),
    );
  }

  void _changeFloor(int floorId) {
    setState(() {
      _currentFloorId = floorId;
      _locationEngine.setFloor(floorId);
    });
    // Ponownie ustaw transformację dla nowego piętra
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setInitialTransform();
    });
  }

  void _centerOnLocation() {
    if (_currentLocation == null) return;

    final screenSize = MediaQuery.of(context).size;
    final centerX = _currentLocation!.x;
    final centerY = _currentLocation!.y;

    final matrix = Matrix4.identity()
      ..scale(_scale)
      ..translate(
        screenSize.width / (2 * _scale) - centerX,
        screenSize.height / (2 * _scale) - centerY,
      );

    _transformationController.value = matrix;
  }

  Future<void> _navigateToPoi(Poi poi) async {
    if (poi.floorId != _currentFloorId) {
      _changeFloor(poi.floorId);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(destination: poi),
      ),
    );
  }

  Future<void> _showSearchScreen() async {
    final selectedPoi = await Navigator.push<Poi>(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(),
      ),
    );

    if (selectedPoi != null) {
      _navigateToPoi(selectedPoi);
    }
  }

  void _showBeaconInfo(Beacon beacon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Beacon: ${beacon.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UUID: ${beacon.uuid}'),
            Text('RSSI: ${beacon.rssi} dBm'),
            Text('Pozycja: (${beacon.x.toStringAsFixed(1)}, ${beacon.y.toStringAsFixed(1)})'),
            Text('Piętro: ${beacon.floorId}'),
          ],
        ),
        actions: [
          TextButton(
            child: Text('Zamknij'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showPoiInfo(Poi poi) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(poi.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Typ: ${_getPoiTypeName(poi.type)}'),
            SizedBox(height: 4),
            Text('Piętro: ${_getFloorName(poi.floorId)}'),
            if (poi.description != null && poi.description!.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(poi.description!),
            ],
            if (poi.equipment.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('Wyposażenie:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              ...poi.equipment.map((e) => Text('• $e')).toList(),
            ],
            if (poi.capacity != null) ...[
              SizedBox(height: 8),
              Text('Pojemność: ${poi.capacity} osób'),
            ],
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(Icons.navigation),
                label: Text('Nawiguj do tego miejsca'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _navigateToPoi(poi);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPoiTypeName(String type) {
    switch (type) {
      case 'room': return 'Sala';
      case 'stairs': return 'Schody';
      case 'elevator': return 'Winda';
      case 'wc': return 'Toaleta';
      case 'exit': return 'Wyjście';
      default: return type;
    }
  }

  String _getFloorName(int floorId) {
    return _floors.firstWhere(
          (floor) => floor.id == floorId,
      orElse: () => Floor(id: floorId, name: 'Piętro $floorId', width: 0, height: 0),
    ).name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMapView(),
          _buildTopPanel(),
          _buildFloorPanel(),
          _buildBottomPanel(),
        ],
      ),
      floatingActionButton: _buildFabs(),
    );
  }

  Widget _buildMapView() {
    final currentFloor = _floors.firstWhere(
          (floor) => floor.id == _currentFloorId,
      orElse: () => _floors.first,
    );

    return InteractiveViewer(
      transformationController: _transformationController,
      boundaryMargin: EdgeInsets.all(100), // Zmniejszony margines
      minScale: 0.1,
      maxScale: 5.0,
      constrained: false, // Dodane dla lepszej kontroli
      child: Container(
        width: currentFloor.width,
        height: currentFloor.height,
        child: Stack(
          children: [
            // Tło mapy - dodano obsługę błędów
            _buildMapBackground(currentFloor),

            // Narysuj siatkę pomocniczą - skala 1:1
            CustomPaint(
              size: Size(currentFloor.width, currentFloor.height),
              painter: _GridPainter(scale: 1.0),
            ),

            // Beacony - bez skalowania pozycji
            ..._beacons
                .where((b) => b.floorId == _currentFloorId)
                .map((beacon) => Positioned(
              left: beacon.x - 5,
              top: beacon.y - 5,
              child: GestureDetector(
                onTap: () => _showBeaconInfo(beacon),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.blue[700],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
            )),

            // Punkty POI - bez skalowania pozycji
            ..._pois
                .where((p) => p.floorId == _currentFloorId)
                .map((poi) => Positioned(
              left: poi.x - 15,
              top: poi.y - 15,
              child: GestureDetector(
                onTap: () => _showPoiInfo(poi),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _getPoiColor(poi.type),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        _getPoiIcon(poi.type),
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        poi.name,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )),

            // Aktualna pozycja użytkownika - bez skalowania pozycji
            if (_currentLocation != null && _currentLocation!.floorId == _currentFloorId)
              Positioned(
                left: _currentLocation!.x - 10,
                top: _currentLocation!.y - 10,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Metoda do budowania tła mapy z PNG
  Widget _buildMapBackground(Floor currentFloor) {
    if (currentFloor.imagePath != null) {
      return Image.asset(
        currentFloor.imagePath!,
        width: currentFloor.width,
        height: currentFloor.height,
        fit: BoxFit.contain,
        // Obsługa błędów ładowania PNG
        errorBuilder: (context, error, stackTrace) {
          print('Błąd ładowania mapy: $error');
          return Container(
            width: currentFloor.width,
            height: currentFloor.height,
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 50, color: Colors.grey[400]),
                  SizedBox(height: 8),
                  Text('Nie można załadować mapy', style: TextStyle(color: Colors.grey[600])),
                  Text('${currentFloor.imagePath}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ],
              ),
            ),
          );
        },
        // Placeholder podczas ładowania
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return frame == null
              ? Container(
            width: currentFloor.width,
            height: currentFloor.height,
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Ładowanie mapy...', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          )
              : child;
        },
      );
    } else {
      return Container(
        width: currentFloor.width,
        height: currentFloor.height,
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 50, color: Colors.grey[400]),
              SizedBox(height: 8),
              Text('Brak mapy dla ${currentFloor.name}',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildTopPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white.withOpacity(0.9),
          child: Row(
            children: [
              Icon(Icons.location_on, color: _isScanning ? Colors.green : Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isScanning
                      ? 'Lokalizowanie...'
                      : 'Lokalizacja wyłączona',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                onPressed: _showSearchScreen,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 18),
                    SizedBox(width: 4),
                    Text('Szukaj'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloorPanel() {
    return Positioned(
      top: 80,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: _floors.map((floor) {
            final isActive = floor.id == _currentFloorId;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _changeFloor(floor.id),
                child: Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: isActive
                        ? Border.all(color: Colors.blue, width: 2)
                        : null,
                    borderRadius: BorderRadius.circular(isActive ? 6 : 0),
                  ),
                  child: Text(
                    '${floor.id}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive ? Colors.blue : Colors.black,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white.withOpacity(0.9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Aktualne piętro: ${_getFloorName(_currentFloorId)}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_currentLocation != null) ...[
              SizedBox(height: 4),
              Text(
                'Pozycja: (${_currentLocation!.x.toStringAsFixed(1)}, ${_currentLocation!.y.toStringAsFixed(1)})',
                style: TextStyle(fontSize: 12),
              ),
            ],
            SizedBox(height: 4),
            Text(
              'Metoda lokalizacji: ${_locationEngine.method.toString().split('.').last}',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFabs() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: 'scan',
          backgroundColor: _isScanning ? Colors.red : Colors.green,
          child: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            if (_isScanning) {
              _bleScanner.stopScan();
              setState(() {
                _isScanning = false;
              });
            } else {
              _startScanning();
            }
          },
          mini: true,
        ),
        SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'location',
          backgroundColor: Colors.blue,
          child: Icon(Icons.my_location),
          onPressed: _centerOnLocation,
          mini: true,
        ),
        SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'reset',
          backgroundColor: Colors.orange,
          child: Icon(Icons.center_focus_strong),
          onPressed: _setInitialTransform,
          mini: true,
        ),
        SizedBox(height: 8),
        FloatingActionButton(
          heroTag: 'menu',
          child: Icon(Icons.menu),
          onPressed: () {
            _showMapMenu();
          },
        ),
      ],
    );
  }

  void _showMapMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.gps_fixed),
              title: Text('Zmień metodę lokalizacji'),
              onTap: () {
                Navigator.pop(context);
                _showLocalizationMethodDialog();
              },
            ),
            ListTile(
              leading: Icon(Icons.refresh),
              title: Text('Zresetuj pozycję'),
              onTap: () {
                Navigator.pop(context);
                _resetLocation();
              },
            ),
            ListTile(
              leading: Icon(Icons.fit_screen),
              title: Text('Dopasuj do ekranu'),
              onTap: () {
                Navigator.pop(context);
                _setInitialTransform();
              },
            ),
            ListTile(
              leading: Icon(Icons.zoom_in),
              title: Text('Przybliż'),
              onTap: () {
                Navigator.pop(context);
                final currentMatrix = _transformationController.value;
                final newMatrix = currentMatrix.clone()..scale(1.2);
                _transformationController.value = newMatrix;
              },
            ),
            ListTile(
              leading: Icon(Icons.zoom_out),
              title: Text('Oddal'),
              onTap: () {
                Navigator.pop(context);
                final currentMatrix = _transformationController.value;
                final newMatrix = currentMatrix.clone()..scale(0.8);
                _transformationController.value = newMatrix;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLocalizationMethodDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Wybierz metodę lokalizacji'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LocalizationMethod.values.map((method) {
            return RadioListTile<LocalizationMethod>(
              title: Text(method.toString().split('.').last),
              value: method,
              groupValue: _locationEngine.method,
              onChanged: (value) {
                Navigator.pop(context);
                if (value != null) {
                  _changeLocalizationMethod(value);
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            child: Text('Anuluj'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  IconData _getPoiIcon(String type) {
    switch (type) {
      case 'room': return Icons.meeting_room;
      case 'stairs': return Icons.stairs;
      case 'elevator': return Icons.elevator;
      case 'wc': return Icons.wc;
      case 'exit': return Icons.exit_to_app;
      default: return Icons.place;
    }
  }

  Color _getPoiColor(String type) {
    switch (type) {
      case 'room': return Colors.blue;
      case 'stairs': return Colors.orange;
      case 'elevator': return Colors.purple;
      case 'wc': return Colors.teal;
      case 'exit': return Colors.red;
      default: return Colors.grey;
    }
  }
}

class _GridPainter extends CustomPainter {
  final double scale;

  _GridPainter({required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final gridSize = 50.0; // Stała wielkość siatki

    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}