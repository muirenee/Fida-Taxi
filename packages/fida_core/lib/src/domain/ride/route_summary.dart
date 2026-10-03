import '../common/geo_point.dart';

final class RouteSummary {
  RouteSummary({
    required this.encodedPolyline,
    required this.distanceMeters,
    required this.durationSeconds,
    this.trafficDurationSeconds,
    this.boundsSouthWest,
    this.boundsNorthEast,
  }) {
    if (encodedPolyline.trim().isEmpty) {
      throw ArgumentError.value(
        encodedPolyline,
        'encodedPolyline',
        'Encoded polyline cannot be empty.',
      );
    }

    if (distanceMeters < 0) {
      throw ArgumentError.value(
        distanceMeters,
        'distanceMeters',
        'Distance cannot be negative.',
      );
    }

    if (durationSeconds < 0) {
      throw ArgumentError.value(
        durationSeconds,
        'durationSeconds',
        'Duration cannot be negative.',
      );
    }

    if (trafficDurationSeconds != null && trafficDurationSeconds! < 0) {
      throw ArgumentError.value(
        trafficDurationSeconds,
        'trafficDurationSeconds',
        'Traffic duration cannot be negative.',
      );
    }

    if ((boundsSouthWest == null) != (boundsNorthEast == null)) {
      throw ArgumentError(
        'Route bounds must contain both southwest and northeast points.',
      );
    }
  }

  final String encodedPolyline;
  final int distanceMeters;
  final int durationSeconds;
  final int? trafficDurationSeconds;
  final GeoPoint? boundsSouthWest;
  final GeoPoint? boundsNorthEast;

  int get effectiveDurationSeconds {
    return trafficDurationSeconds ?? durationSeconds;
  }

  RouteSummary copyWith({
    String? encodedPolyline,
    int? distanceMeters,
    int? durationSeconds,
    int? trafficDurationSeconds,
    GeoPoint? boundsSouthWest,
    GeoPoint? boundsNorthEast,
    bool clearTrafficDuration = false,
    bool clearBounds = false,
  }) {
    return RouteSummary(
      encodedPolyline: encodedPolyline ?? this.encodedPolyline,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trafficDurationSeconds: clearTrafficDuration
          ? null
          : trafficDurationSeconds ?? this.trafficDurationSeconds,
      boundsSouthWest: clearBounds
          ? null
          : boundsSouthWest ?? this.boundsSouthWest,
      boundsNorthEast: clearBounds
          ? null
          : boundsNorthEast ?? this.boundsNorthEast,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'encoded_polyline': encodedPolyline,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'traffic_duration_seconds': trafficDurationSeconds,
      'bounds_south_west': boundsSouthWest?.toJson(),
      'bounds_north_east': boundsNorthEast?.toJson(),
    };
  }

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    final encodedPolylineValue = json['encoded_polyline'];
    final distanceValue = json['distance_meters'];
    final durationValue = json['duration_seconds'];
    final trafficDurationValue = json['traffic_duration_seconds'];

    if (encodedPolylineValue is! String) {
      throw const FormatException(
        'RouteSummary.encoded_polyline must be a string.',
      );
    }

    if (distanceValue is! num) {
      throw const FormatException(
        'RouteSummary.distance_meters must be numeric.',
      );
    }

    if (durationValue is! num) {
      throw const FormatException(
        'RouteSummary.duration_seconds must be numeric.',
      );
    }

    if (trafficDurationValue != null && trafficDurationValue is! num) {
      throw const FormatException(
        'RouteSummary.traffic_duration_seconds must be numeric or null.',
      );
    }

    return RouteSummary(
      encodedPolyline: encodedPolylineValue,
      distanceMeters: distanceValue.toInt(),
      durationSeconds: durationValue.toInt(),
      trafficDurationSeconds: trafficDurationValue == null
          ? null
          : (trafficDurationValue as num).toInt(),
      boundsSouthWest: _optionalGeoPoint(
        json['bounds_south_west'],
        'bounds_south_west',
      ),
      boundsNorthEast: _optionalGeoPoint(
        json['bounds_north_east'],
        'bounds_north_east',
      ),
    );
  }

  static GeoPoint? _optionalGeoPoint(Object? value, String fieldName) {
    if (value == null) {
      return null;
    }

    if (value is! Map<Object?, Object?>) {
      throw FormatException(
        'RouteSummary.$fieldName must be an object or null.',
      );
    }

    return GeoPoint.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RouteSummary &&
            other.encodedPolyline == encodedPolyline &&
            other.distanceMeters == distanceMeters &&
            other.durationSeconds == durationSeconds &&
            other.trafficDurationSeconds == trafficDurationSeconds &&
            other.boundsSouthWest == boundsSouthWest &&
            other.boundsNorthEast == boundsNorthEast;
  }

  @override
  int get hashCode => Object.hash(
    encodedPolyline,
    distanceMeters,
    durationSeconds,
    trafficDurationSeconds,
    boundsSouthWest,
    boundsNorthEast,
  );

  @override
  String toString() {
    return 'RouteSummary(distanceMeters: $distanceMeters, '
        'durationSeconds: $durationSeconds, '
        'trafficDurationSeconds: $trafficDurationSeconds)';
  }
}
