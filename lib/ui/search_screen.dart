import 'package:flutter/material.dart';
import '../models/poi.dart';
import '../data/local_storage_service.dart';
import '../models/floor.dart';
import '../ui/map_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final LocalStorageService _storage = LocalStorageService();
  final TextEditingController _searchController = TextEditingController();

  List<Poi> _allPois = [];
  List<Poi> _filteredPois = [];
  String _searchQuery = '';
  String? _selectedCategory;

  // Lista dostępnych kategorii POI
  final List<String?> _categories = [
    null, // Wszystkie kategorie
    'room',
    'stairs',
    'elevator',
    'wc',
    'exit'
  ];

  // Mapowanie typu POI na jego nazwę po polsku
  final Map<String, String> _categoryNames = {
    'room': 'Sala',
    'stairs': 'Schody',
    'elevator': 'Winda',
    'wc': 'Toaleta',
    'exit': 'Wyjście',
  };

  // Lista dostępnych pięter
  final List<Floor> _floors = [
    Floor(id: 0, name: 'Parter', width: 8.0, height: 6.0),
    Floor(id: 1, name: '1 Piętro', width: 8.0, height: 6.0),
    Floor(id: 2, name: '2 Piętro', width: 7.5, height: 5.8),
  ];

  @override
  void initState() {
    super.initState();
    _loadPois();
  }

  Future<void> _loadPois() async {
    final pois = await _storage.loadPois();
    setState(() {
      _allPois = pois;
      _filteredPois = pois;
    });
  }

  void _filterPois() {
    setState(() {
      _filteredPois = _allPois.where((poi) {
        // Filtrowanie według wyszukiwanej frazy
        final matchesQuery = _searchQuery.isEmpty ||
            poi.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (poi.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            poi.equipment.any((item) => item.toLowerCase().contains(_searchQuery.toLowerCase()));

        // Filtrowanie według kategorii
        final matchesCategory = _selectedCategory == null || poi.type == _selectedCategory;

        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  String _getFloorName(int floorId) {
    return _floors.firstWhere((floor) => floor.id == floorId, orElse: () => Floor(id: floorId, name: 'Piętro $floorId', width: 0, height: 0)).name;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wyszukaj POI'),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: () {
              _showFilterDialog(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Panel wyszukiwania
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Szukaj',
                hintText: 'Wpisz nazwę, opis lub wyposażenie',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                    _filterPois();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _filterPois();
              },
            ),
          ),

          // Filtr kategorii
          if (_selectedCategory != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Chip(
                avatar: Icon(_getPoiIcon(_selectedCategory!), size: 18),
                label: Text(_categoryNames[_selectedCategory] ?? _selectedCategory!),
                deleteIcon: Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() {
                    _selectedCategory = null;
                  });
                  _filterPois();
                },
              ),
            ),

          // Informacja o liczbie wyników
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Znaleziono ${_filteredPois.length} wyników',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),

          // Lista wyników
          Expanded(
            child: _filteredPois.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Brak wyników wyszukiwania',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _filteredPois.length,
              itemBuilder: (context, index) {
                final poi = _filteredPois[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getPoiColor(poi.type),
                      child: Icon(_getPoiIcon(poi.type), color: Colors.white),
                    ),
                    title: Text(poi.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getFloorName(poi.floorId)),
                        if (poi.description != null && poi.description!.isNotEmpty)
                          Text(
                            poi.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: Icon(Icons.chevron_right),
                    onTap: () {
                      _showPoiDetails(poi);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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

  void _showPoiDetails(Poi poi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nagłówek z typem i nazwą
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getPoiColor(poi.type),
                    child: Icon(_getPoiIcon(poi.type), color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poi.name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_categoryNames[poi.type] ?? poi.type} • ${_getFloorName(poi.floorId)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // Zdjęcie POI (jeśli dostępne)
              if (poi.imagePath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    poi.imagePath!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: double.infinity,
                        height: 100,
                        color: Colors.grey[200],
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text(
                                'Brak zdjęcia',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 16),
              ],

              // Opis
              if (poi.description != null && poi.description!.isNotEmpty) ...[
                Text(
                  'Opis',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(poi.description!),
                SizedBox(height: 16),
              ],

              // Wyposażenie
              if (poi.equipment.isNotEmpty) ...[
                Text(
                  'Wyposażenie',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: poi.equipment.map((item) => Chip(
                    label: Text(item),
                    backgroundColor: Colors.grey[200],
                  )).toList(),
                ),
                SizedBox(height: 16),
              ],

              // Pojemność (jeśli określona)
              if (poi.capacity != null) ...[
                Row(
                  children: [
                    Icon(Icons.people, color: Colors.grey[600]),
                    SizedBox(width: 8),
                    Text(
                      'Pojemność: ${poi.capacity} osób',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
              ],

              // Przycisk nawigacji
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
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Filtruj według kategorii'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: _categories.map((category) {
              final isSelected = _selectedCategory == category;
              return ListTile(
                leading: category != null
                    ? Icon(_getPoiIcon(category), color: _getPoiColor(category))
                    : Icon(Icons.all_inclusive),
                title: Text(category != null ? _categoryNames[category] ?? category : 'Wszystkie kategorie'),
                selected: isSelected,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _selectedCategory = category;
                  });
                  _filterPois();
                },
              );
            }).toList(),
          ),
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

  void _navigateToPoi(Poi poi) {
    // Bezpośrednie przejście do ekranu mapy z przekazanym POI
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapScreen(),
        settings: RouteSettings(arguments: poi),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}