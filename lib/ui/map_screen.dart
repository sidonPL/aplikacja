import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
import 'navigation_screen.dart';
import 'search_screen.dart';

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

  // Parametry mapy
  double _scale = 1.0; // piksele na metr
  Offset _mapOffset = Offset(0, 0);

  // Kontroler transformacji mapy
  final TransformationController _transformationController = TransformationController();

  // Lista pięter
  final List<Floor> _floors = [
    Floor(id: 0, name: 'Parter', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_0.png'),
    Floor(id: 1, name: '1 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_1.svg'),
    Floor(id: 2, name: '2 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_2.svg'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
    _checkPermissions();
    _loadBeacons();
    _loadPois();
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
    // Zarządzanie skanowaniem BLE w zależności od stanu aplikacji
    if (state == AppLifecycleState.resumed) {
      if (_isScanning) _startScanning();
    } else if (state == AppLifecycleState.paused) {
      _bleScanner.stopScan();
    }
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
      // Aktualizuj beacony z rssi
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

        // Jeśli zmieniło się piętro, zaktualizuj je
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
  }

  void _centerOnLocation() {
    if (_currentLocation == null) return;

    final centerX = _currentLocation!.x * _scale;
    final centerY = _currentLocation!.y * _scale;

    // Oblicz nową macierz transformacji dla centrowania mapy
    final matrix = Matrix4.identity()
      ..translate(-centerX + MediaQuery.of(context).size.width / 2,
          -centerY + MediaQuery.of(context).size.height / 2)
      ..scale(_scale / 10); // Ustaw skalę

    _transformationController.value = matrix;
  }

  Future<void> _navigateToPoi(Poi poi) async {
    // Jeśli POI jest na innym piętrze, zmień piętro
    if (poi.floorId != _currentFloorId) {
      _changeFloor(poi.floorId);
    }

    // Przejdź do ekranu nawigacji
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
          // Mapa
          _buildMapView(),

          // Panel górny
          _buildTopPanel(),

          // Panel przełączania pięter
          _buildFloorPanel(),

          // Panel informacyjny na dole
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
      boundaryMargin: EdgeInsets.all(500), // Większy margines dla swobodnego przesuwania
      minScale: 0.1,
      maxScale: 5.0,
      child: SizedBox(
        width: currentFloor.width * _scale,
        height: currentFloor.height * _scale,
        child: Stack(
          children: [
            // Tło mapy (plan piętra)
            if (currentFloor.imagePath != null)
              SvgPicture.asset(
                currentFloor.imagePath!,
                width: currentFloor.width * _scale,
                height: currentFloor.height * _scale,
                fit: BoxFit.contain,
              )
            else
              Container(
                width: currentFloor.width * _scale,
                height: currentFloor.height * _scale,
                color: Colors.grey[200],
              ),

            // Narysuj siatkę pomocniczą
            CustomPaint(
              size: Size(currentFloor.width * _scale, currentFloor.height * _scale),
              painter: _GridPainter(scale: _scale),
            ),

            // Beacony
            ..._beacons
                .where((b) => b.floorId == _currentFloorId)
                .map((beacon) => Positioned(
              left: beacon.x * _scale - 5,
              top: beacon.y * _scale - 5,
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

            // Punkty POI
            ..._pois
                .where((p) => p.floorId == _currentFloorId)
                .map((poi) => Positioned(
              left: poi.x * _scale - 15,
              top: poi.y * _scale - 15,
              child: GestureDetector(
                onTap: () => _showPoiInfo(poi),
                child: Column(
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

            // Aktualna pozycja użytkownika
            if (_currentLocation != null && _currentLocation!.floorId == _currentFloorId)
              Positioned(
                left: _currentLocation!.x * _scale - 10,
                top: _currentLocation!.y * _scale - 10,
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
            // Aktualne piętro
            Text(
              'Aktualne piętro: ${_getFloorName(_currentFloorId)}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            // Aktualna pozycja
            if (_currentLocation != null) ...[
              SizedBox(height: 4),
              Text(
                'Pozycja: (${_currentLocation!.x.toStringAsFixed(1)}, ${_currentLocation!.y.toStringAsFixed(1)})',
                style: TextStyle(fontSize: 12),
              ),
            ],

            // Metoda lokalizacji
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
        // Przycisk włączania/wyłączania skanowania
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

        // Przycisk centrowania na pozycji użytkownika
        FloatingActionButton(
          heroTag: 'location',
          backgroundColor: Colors.blue,
          child: Icon(Icons.my_location),
          onPressed: _centerOnLocation,
          mini: true,
        ),
        SizedBox(height: 8),

        // Przycisk menu z opcjami mapy
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
              leading: Icon(Icons.zoom_in),
              title: Text('Przybliż'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _scale *= 1.2;
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.zoom_out),
              title: Text('Oddal'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _scale /= 1.2;
                });
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

    // Rysuj siatkę co 5 metrów
    final gridSize = 5 * scale;

    // Linie pionowe
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Linie poziome
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}