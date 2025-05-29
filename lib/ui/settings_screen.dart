import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/localization_method_enum.dart';
import '../config/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  LocalizationMethod? _selected;
  bool _isDarkMode = false;
  double _updateInterval = 500;

  @override
  void initState() {
    super.initState();
    _selected = LocalizationMethod.hybrid;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    setState(() {
      _isDarkMode = themeProvider.isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(
        children: [
          // Sekcja lokalizacji
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
            child: Text(
              'Metoda lokalizacji',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...LocalizationMethod.values.map((m) {
            return RadioListTile<LocalizationMethod>(
              title: Text(m.toString().split('.').last),
              value: m,
              groupValue: _selected,
              onChanged: (val) => setState(() => _selected = val),
            );
          }),

          // Nowa sekcja: częstotliwość aktualizacji pozycji
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 24.0, bottom: 8.0),
            child: Text(
              'Częstotliwość aktualizacji pozycji (ms)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Slider(
            value: _updateInterval,
            min: 200,
            max: 2000,
            divisions: 18,
            label: _updateInterval.round().toString(),
            onChanged: (val) {
              setState(() {
                _updateInterval = val;
              });
              // TODO: Przekazać do LocationEngine
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('Aktualnie: ${_updateInterval.round()} ms'),
          ),

          // Sekcja wyglądu
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 24.0, bottom: 8.0),
            child: Text(
              'Wygląd aplikacji',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            title: const Text('Tryb ciemny'),
            value: _isDarkMode,
            onChanged: (bool value) {
              final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
              themeProvider.setDarkMode(value);
              setState(() {
                _isDarkMode = value;
              });
            },
            secondary: Icon(_isDarkMode ? Icons.dark_mode : Icons.light_mode),
          ),
        ],
      ),
    );
  }
}