import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'search_screen.dart';
import 'beacons_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    MapScreen(),
    SearchScreen(),
    BeaconsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Szukaj'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Beacony'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ustawienia'),
        ],
      ),
    );
  }
}