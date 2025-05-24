// lib/ui/beacons_screen.dart
import 'package:flutter/material.dart';
import '../services/ble_scanner.dart';
import '../models/beacon.dart';

class BeaconsScreen extends StatefulWidget {
  @override
  _BeaconsScreenState createState() => _BeaconsScreenState();
}

class _BeaconsScreenState extends State<BeaconsScreen> {
  final BleScanner _scanner = BleScanner();
  List<Beacon> _beacons = [];

  @override
  void initState() {
    super.initState();
    _scanner.startScan();
    _scanner.scanResults.listen((list) {
      setState(() => _beacons = list);
    });
  }

  @override
  void dispose() {
    _scanner.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_beacons.isEmpty) {
      return Center(child: Text('No beacons found'));
    }
    return ListView.builder(
      itemCount: _beacons.length,
      itemBuilder: (context, index) {
        final b = _beacons[index];
        return ListTile(
          leading: Icon(Icons.bluetooth),
          title: Text(b.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UUID: ${b.uuid}'),
              Text('RSSI: ${b.rssi} dBm'),
            ],
          ),
        );
      },
    );
  }
}
