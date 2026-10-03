final class GeoPoint {
  GeoPoint({required double latitude, required double longitude})
    : latitude = _validateLatitude(latitude),
      longitude = _validateLongitude(longitude);

  final double latitude;
  final double longitude;

  static double _validateLatitude(double value) {
    if (!value.isFinite || value < -90 || value > 90) {
      throw ArgumentError.value(
        value,
        'latitude',
        'Latitude must be finite and between -90 and 90.',
      );
    }

    return value;
  }

  static double _validateLongitude(double value) {
    if (!value.isFinite || value < -180 || value > 180) {
      throw ArgumentError.value(
        value,
        'longitude',
        'Longitude must be finite and between -180 and 180.',
      );
    }

    return value;
  }

  GeoPoint copyWith({double? latitude, double? longitude}) {
    return GeoPoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'latitude': latitude, 'longitude': longitude};
  }

  factory GeoPoint.fromJson(Map<String, dynamic> json) {
    final latitudeValue = json['latitude'];
    final longitudeValue = json['longitude'];

    if (latitudeValue is! num) {
      throw const FormatException('GeoPoint.latitude must be numeric.');
    }

    if (longitudeValue is! num) {
      throw const FormatException('GeoPoint.longitude must be numeric.');
    }

    return GeoPoint(
      latitude: latitudeValue.toDouble(),
      longitude: longitudeValue.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GeoPoint &&
            other.latitude == latitude &&
            other.longitude == longitude;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() {
    return 'GeoPoint(latitude: $latitude, longitude: $longitude)';
  }
}
