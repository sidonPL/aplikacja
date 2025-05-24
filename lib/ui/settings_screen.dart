import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/localization_method_enum.dart';
import '../config/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LocalizationMethod? _selected;
  bool _isDarkMode = false;

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
          }).toList(),

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