import '../models/poi.dart';
import 'local_storage_service.dart';

class PoiRepository {
  final LocalStorageService _storage = LocalStorageService();
  Future<List<Poi>> getPois() => _storage.loadPois();
}