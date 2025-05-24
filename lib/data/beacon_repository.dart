import '../models/beacon.dart';
import 'local_storage_service.dart';

class BeaconRepository {
  final LocalStorageService _storage = LocalStorageService();
  Future<List<Beacon>> getBeacons() => _storage.loadBeacons();
}