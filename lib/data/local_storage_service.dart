import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/beacon.dart';
import '../models/poi.dart';
import '../models/waypoint.dart';
import '../models/connection.dart';

class LocalStorageService {
  Future<List<Beacon>> loadBeacons() async {
    final data = await rootBundle.loadString('assets/data/beacons.json');
    final List jsonList = json.decode(data) as List;
    return jsonList.map((e) => Beacon.fromJson(e)).toList();
  }

  Future<List<Poi>> loadPois() async {
    final data = await rootBundle.loadString('assets/data/pois.json');
    final List jsonList = json.decode(data) as List;
    return jsonList.map((e) => Poi.fromJson(e)).toList();
  }

  Future<List<Waypoint>> loadWaypoints() async {
    final data = await rootBundle.loadString('assets/data/waypoints.json');
    final List jsonList = json.decode(data) as List;
    return jsonList.map((e) => Waypoint.fromJson(e)).toList();
  }

  Future<List<Connection>> loadConnections() async {
    final data = await rootBundle.loadString('assets/data/connections.json');
    final List jsonList = json.decode(data) as List;
    return jsonList.map((e) => Connection.fromJson(e)).toList();
  }
}