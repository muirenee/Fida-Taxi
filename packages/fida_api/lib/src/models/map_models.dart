import 'package:fida_core/fida_core.dart';

final class MapPlace {
  const MapPlace({required this.id, required this.label, required this.point});

  final String id;
  final String label;
  final GeoPoint point;

  factory MapPlace.fromJson(Map<String, dynamic> json) {
    return MapPlace(
      id: _requiredString(json['id'], 'id'),
      label: _requiredString(json['label'], 'label'),
      point: GeoPoint(
        latitude: _requiredDouble(json['latitude'], 'latitude'),
        longitude: _requiredDouble(json['longitude'], 'longitude'),
      ),
    );
  }
}

final class RoutePreview {
  const RoutePreview({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
  });

  final int distanceMeters;
  final int durationSeconds;
  final List<GeoPoint> points;

  double get distanceKm => distanceMeters / 1000;
  Duration get duration => Duration(seconds: durationSeconds);

  factory RoutePreview.fromJson(Map<String, dynamic> json) {
    final rawCoordinates = json['coordinates'];
    if (rawCoordinates is! List<Object?>) {
      throw const FormatException('coordinates must be an array.');
    }

    return RoutePreview(
      distanceMeters: _requiredInt(json['distance_meters'], 'distance_meters'),
      durationSeconds: _requiredInt(
        json['duration_seconds'],
        'duration_seconds',
      ),
      points: rawCoordinates
          .map((value) {
            if (value is! Map<Object?, Object?>) {
              throw const FormatException(
                'route coordinate must be an object.',
              );
            }
            final coordinate = Map<String, dynamic>.from(value);
            return GeoPoint(
              latitude: _requiredDouble(coordinate['latitude'], 'latitude'),
              longitude: _requiredDouble(coordinate['longitude'], 'longitude'),
            );
          })
          .toList(growable: false),
    );
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
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
