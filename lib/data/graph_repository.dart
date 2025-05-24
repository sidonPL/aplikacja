import '../models/waypoint.dart';
import '../models/connection.dart';
import 'local_storage_service.dart';

class GraphRepository {
  final LocalStorageService _storage = LocalStorageService();
  Future<List<Waypoint>> getWaypoints() => _storage.loadWaypoints();
  Future<List<Connection>> getConnections() => _storage.loadConnections();
}