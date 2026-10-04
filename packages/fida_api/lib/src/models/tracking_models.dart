import 'package:fida_core/fida_core.dart';

final class DriverLocationAck {
  const DriverLocationAck({
    required this.driverId,
    required this.point,
    required this.observedAt,
    required this.presenceTtlSeconds,
    this.activeTripId,
  });

  final String driverId;
  final String? activeTripId;
  final GeoPoint point;
  final DateTime observedAt;
  final int presenceTtlSeconds;

  factory DriverLocationAck.fromJson(Map<String, dynamic> json) {
    return DriverLocationAck(
      driverId: _requiredString(json['driver_id'], 'driver_id'),
      activeTripId: _optionalString(json['active_trip_id']),
      point: GeoPoint(
        latitude: _requiredDouble(json['latitude'], 'latitude'),
        longitude: _requiredDouble(json['longitude'], 'longitude'),
      ),
      observedAt: DateTime.parse(
        _requiredString(json['observed_at'], 'observed_at'),
      ).toUtc(),
      presenceTtlSeconds: _requiredInt(
        json['presence_ttl_seconds'],
        'presence_ttl_seconds',
      ),
    );
  }
}

final class TripDriverLocation {
  const TripDriverLocation({
    required this.driverId,
    required this.point,
    this.observedAt,
  });

  final String driverId;
  final GeoPoint point;
  final DateTime? observedAt;

  factory TripDriverLocation.fromEnvelope(Map<String, dynamic> json) {
    final driverId = _requiredString(json['driver_id'], 'driver_id');
    final rawLocation = json['location'];
    if (rawLocation is! Map<Object?, Object?>) {
      throw const FormatException('location must be an object.');
    }
    final location = Map<String, dynamic>.from(rawLocation);
    final rawObservedAt = location['observed_at'];

    return TripDriverLocation(
      driverId: driverId,
      point: GeoPoint(
        latitude: _requiredDouble(location['latitude'], 'location.latitude'),
        longitude: _requiredDouble(location['longitude'], 'location.longitude'),
      ),
      observedAt: rawObservedAt is String && rawObservedAt.trim().isNotEmpty
          ? DateTime.parse(rawObservedAt).toUtc()
          : null,
    );
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected string or null.');
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double _requiredDouble(Object? value, String field) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$field must be numeric.');
  }
  return value.toDouble();
}

int _requiredInt(Object? value, String field) {
  if (value is! num || value != value.roundToDouble()) {
    throw FormatException('$field must be an integer.');
  }
  return value.toInt();
}
