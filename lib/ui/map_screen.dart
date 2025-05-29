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
  const MapScreen({super.key});

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
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
  double _scale = 10.0;

  // Kontroler transformacji mapy
  final TransformationController _transformationController = TransformationController();

  // Lista pięter
  final List<Floor> _floors = [
    Floor(id: 0, name: 'Parter', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_0.png'),
    Floor(id: 1, name: '1 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_1.png'),
    Floor(id: 2, name: '2 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_2.png'),
    Floor(id: 3, name: '3 Piętro', width: 2200.0, height: 878.0, imagePath: 'assets/images/Floor_3.png'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
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

    // Ustaw transformację mapy, aby była wyśrodkowana
    final centerX = (screenSize.width - mapWidth * optimalScale) / 2;
    final centerY = (screenSize.height - 200 - mapHeight * optimalScale) / 2 + 100; // 100px dla górnego panelu

    _transformationController.value = Matrix4.identity()
      ..translate(centerX, centerY)
      ..scale(optimalScale);
  }

  Future<void> _checkPermissions() async {
    final hasPermissions = await PermissionService.hasAllPermissions();
    if (mounted) {
      setState(() {
        _hasPermissions = hasPermissions;
      });
    }

    if (!hasPermissions) {
      final granted = await PermissionService.requestAll();
      if (mounted) {
        setState(() {
          _hasPermissions = granted;
        });
      }
    }

    if (_hasPermissions && mounted) {
      await _startScanning();
    }
  }

  Future<void> _loadBeacons() async {
    final beacons = await _beaconRepository.getBeacons();
    if (mounted) {
      setState(() {
        _beacons = beacons;
      });
    }
  }

  Future<void> _loadPois() async {
    final pois = await _poiRepository.getPois();
    if (mounted) {
      setState(() {
        _pois = pois;
      });
    }
  }

  Future<void> _startScanning() async {
    if (!_hasPermissions || _isScanning) return;

    if (mounted) {
      setState(() {
        _isScanning = true;
      });
    }

    _bleScanner.startScan();

    _bleSubscription = _bleScanner.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Aktualizuj RSSI dla istniejących beaconów
          for (final result in results) {
            final index = _beacons.indexWhere((b) => b.uuid == result.uuid);
            if (index != -1) {
              _beacons[index] = _beacons[index].copyWith(rssi: result.rssi);
            }
          }
        });
      }
    });

    if (!_isLocationEngineRunning) {
      _startLocationEngine();
    }
  }

  void _startLocationEngine() {
    if (mounted) {
      setState(() {
        _isLocationEngineRunning = true;
      });
    }

    _locationSubscription = _locationEngine.location$.listen((location) {
      if (mounted) {
        setState(() {
          _currentLocation = location;
          // Aktualizuj piętro jeśli się zmieniło
          if (_currentFloorId != location.floorId) {
            _currentFloorId = location.floorId;
            _locationEngine.setFloor(_currentFloorId);
          }
        });
      }
    });
  }

  void _changeFloor(int floorId) {
    setState(() {
      _currentFloorId = floorId;
    });
    _locationEngine.setFloor(floorId);
    _setInitialTransform(); // Ustaw ponownie transformację dla nowego piętra
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
      case 'wc': return Colors.brown;
      case 'exit': return Colors.red;
      default: return Colors.grey;
    }
  }

  // Poprawiona metoda nawigacji
  Future<void> _navigateToDestination(Poi poi) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Sprawdź czy skanowanie jest aktywne
    if (!_isScanning) {
      await _startScanning();
      // Poczekaj chwilę na pierwsze wyniki
      await Future.delayed(const Duration(seconds: 2));
    }

    // Sprawdź czy mamy jakiekolwiek beacony
    if (_beacons.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Brak sygnału beaconów. Upewnij się, że Bluetooth jest włączony.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Sprawdź czy mamy aktualną lokalizację
    if (_currentLocation == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Oczekiwanie na lokalizację...'),
          backgroundColor: Colors.blue,
        ),
      );
      // Poczekaj na lokalizację
      await Future.delayed(const Duration(seconds: 3));

      if (_currentLocation == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Nie udało się określić lokalizacji. Sprawdź czy jesteś w zasięgu beaconów.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    navigator.push(
      MaterialPageRoute(
        builder: (context) => NavigationScreen(destination: poi),
      ),
    );
  }

  Widget _buildMapContent() {
    final currentFloor = _floors.firstWhere(
          (floor) => floor.id == _currentFloorId,
      orElse: () => _floors.first,
    );

    return InteractiveViewer(
      transformationController: _transformationController,
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.1,
      maxScale: 5.0,
      child: SizedBox(
        width: currentFloor.width,
        height: currentFloor.height,
        child: Stack(
          children: [
            // Tło mapy
            if (currentFloor.imagePath != null)
              Positioned.fill(
                child: Image.asset(
                  currentFloor.imagePath!,
                  fit: BoxFit.contain,
                ),
              )
            else
              Positioned.fill(
                child: Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: Text(
                      currentFloor.name,
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ),

            // Beacony na aktualnym piętrze
            ..._beacons
                .where((beacon) => beacon.floorId == _currentFloorId)
                .map((beacon) => Positioned(
              left: beacon.x - 10,
              top: beacon.y - 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: beacon.rssi > -80 ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    beacon.rssi.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )),

            // POI na aktualnym piętrze
            ..._pois
                .where((poi) => poi.floorId == _currentFloorId)
                .map((poi) => Positioned(
              left: poi.x - 15,
              top: poi.y - 15,
              child: GestureDetector(
                onTap: () => _showPoiDetails(poi),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _getPoiColor(poi.type),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    _getPoiIcon(poi.type),
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            )),

            // Aktualna pozycja użytkownika
            if (_currentLocation != null && _currentLocation!.floorId == _currentFloorId)
              Positioned(
                left: _currentLocation!.x - 12,
                top: _currentLocation!.y - 12,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPoiDetails(Poi poi) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getPoiIcon(poi.type), color: _getPoiColor(poi.type)),
                const SizedBox(width: 8),
                Text(
                  poi.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (poi.description != null) ...[
              const SizedBox(height: 8),
              Text(poi.description!),
            ],
            if (poi.equipment.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Wyposażenie:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              ...poi.equipment.map((item) => Text('• $item')),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _navigateToDestination(poi);
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('Nawiguj'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Zamknij'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mapa - ${_floors.firstWhere((f) => f.id == _currentFloorId).name}'),
        actions: [
          // Przycisk wyszukiwania
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SearchScreen()),
              );
              if (result != null && result is Poi && mounted) {
                _navigateToDestination(result);
              }
            },
          ),
          // Przycisk ustawień
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Panel statusu
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _hasPermissions && _isScanning ? Colors.green[100] : Colors.red[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _hasPermissions && _isScanning ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _hasPermissions && _isScanning ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasPermissions && _isScanning
                        ? 'Bluetooth aktywny | Beacony: ${_beacons.length} | Pozycja: ${_currentLocation != null ? "OK" : "Szukanie..."}'
                        : 'Bluetooth wyłączony lub brak uprawnień',
                    style: TextStyle(
                      color: _hasPermissions && _isScanning ? Colors.green[800] : Colors.red[800],
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!_hasPermissions || !_isScanning)
                  TextButton(
                    onPressed: _hasPermissions ? _startScanning : _checkPermissions,
                    child: Text(
                      _hasPermissions ? 'Włącz' : 'Uprawnienia',
                      style: TextStyle(color: Colors.red[800]),
                    ),
                  ),
              ],
            ),
          ),

          // Selektor pięter
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _floors.length,
              itemBuilder: (context, index) {
                final floor = _floors[index];
                final isSelected = floor.id == _currentFloorId;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: ElevatedButton(
                    onPressed: () => _changeFloor(floor.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Theme.of(context).primaryColor : Colors.grey[300],
                      foregroundColor: isSelected ? Colors.white : Colors.black,
                    ),
                    child: Text(floor.name),
                  ),
                );
              },
            ),
          ),

          // Mapa
          Expanded(
            child: _buildMapContent(),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "center",
            mini: true,
            onPressed: _setInitialTransform,
            tooltip: 'Wyśrodkuj mapę',
            child: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "location",
            mini: true,
            onPressed: _currentLocation != null
                ? () {
              // Przejdź do piętra z aktualną pozycją
              if (_currentLocation!.floorId != _currentFloorId) {
                _changeFloor(_currentLocation!.floorId);
              }

              // Wyśrodkuj na aktualnej pozycji
              final screenSize = MediaQuery.of(context).size;
              final centerX = screenSize.width / 2 - _currentLocation!.x * _scale;
              final centerY = (screenSize.height - 200) / 2 - _currentLocation!.y * _scale;

              _transformationController.value = Matrix4.identity()
                ..translate(centerX, centerY)
                ..scale(_scale);
            }
                : null,
            backgroundColor: _currentLocation != null ? null : Colors.grey,
            tooltip: 'Moja pozycja',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ustawienia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Metoda lokalizacji'),
              subtitle: Text(_locationEngine.method.toString().split('.').last),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showLocalizationMethodDialog(),
            ),
            ListTile(
              title: const Text('Reset pozycji'),
              subtitle: const Text('Wyzeruj obliczoną pozycję'),
              trailing: const Icon(Icons.refresh),
              onTap: () {
                _locationEngine.resetPosition();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pozycja została zresetowana')),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zamknij'),
          ),
        ],
      ),
    );
  }

  void _showLocalizationMethodDialog() {
    Navigator.pop(context); // Zamknij dialog ustawień
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Metoda lokalizacji'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LocalizationMethod.values.map((method) {
            return RadioListTile<LocalizationMethod>(
              title: Text(method.toString().split('.').last),
              value: method,
              groupValue: _locationEngine.method,
              onChanged: (value) {
                setState(() {
                  _locationEngine.method = value!;
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}