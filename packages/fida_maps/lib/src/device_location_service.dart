import 'package:fida_core/fida_core.dart';
import 'package:geolocator/geolocator.dart';

final class LocationAccessException implements Exception {
  const LocationAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DeviceLocationService {
  const DeviceLocationService();

  Future<GeoPoint> current() async {
    await _ensurePermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return _toPoint(position);
  }

  Stream<GeoPoint> watch({int distanceFilterMeters = 10}) async* {
    await _ensurePermission();
    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
    await for (final position in Geolocator.getPositionStream(
      locationSettings: settings,
    )) {
      yield _toPoint(position);
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();

  Future<void> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationAccessException(
        'Location services are disabled. Enable GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationAccessException(
        'Location permission is required to use Fida Taxi.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationAccessException(
        'Location permission is permanently denied. Enable it in app settings.',
      );
    }
  }

  GeoPoint _toPoint(Position position) {
    return GeoPoint(latitude: position.latitude, longitude: position.longitude);
  }
}
