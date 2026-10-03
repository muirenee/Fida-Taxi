import 'package:fida_core/fida_core.dart';
import 'package:test/test.dart';

void main() {
  group('GeoPoint', () {
    test('accepts valid Kigali coordinates', () {
      final point = GeoPoint(
        latitude: -1.9441,
        longitude: 30.0619,
      );

      expect(point.latitude, -1.9441);
      expect(point.longitude, 30.0619);
    });

    test('rejects invalid latitude', () {
      expect(
        () => GeoPoint(
          latitude: 91,
          longitude: 30,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Money', () {
    test('normalizes currency and adds equal currencies', () {
      final first = Money(
        minorUnits: 1000,
        currency: 'rwf',
      );

      final second = Money(
        minorUnits: 250,
        currency: 'RWF',
      );

      expect(
        first + second,
        Money(
          minorUnits: 1250,
          currency: 'RWF',
        ),
      );
    });

    test('rejects mixed currencies', () {
      final rwf = Money(
        minorUnits: 1000,
        currency: 'RWF',
      );

      final usd = Money(
        minorUnits: 1000,
        currency: 'USD',
      );

      expect(
        () => rwf + usd,
        throwsArgumentError,
      );
    });
  });

  group('Ride', () {
    test('round-trips through JSON', () {
      final createdAt = DateTime.utc(
        2026,
        10,
        3,
        10,
      );

      final ride = Ride(
        id: 'ride_001',
        riderId: 'rider_001',
        assignedDriverId: 'driver_001',
        status: RideStatus.driverAssigned,
        pickup: GeoPoint(
          latitude: -1.9441,
          longitude: 30.0619,
        ),
        dropoff: GeoPoint(
          latitude: -1.9706,
          longitude: 30.1044,
        ),
        vehicleType: VehicleType.standard,
        quotedFare: Money(
          minorUnits: 8500,
          currency: 'RWF',
        ),
        route: RouteSummary(
          encodedPolyline: 'encoded-polyline',
          distanceMeters: 8400,
          durationSeconds: 1200,
          trafficDurationSeconds: 1350,
          boundsSouthWest: GeoPoint(
            latitude: -1.99,
            longitude: 30.01,
          ),
          boundsNorthEast: GeoPoint(
            latitude: -1.90,
            longitude: 30.12,
          ),
        ),
        revision: 4,
        createdAt: createdAt,
        updatedAt: createdAt.add(
          const Duration(minutes: 1),
        ),
      );

      final decoded = Ride.fromJson(ride.toJson());

      expect(decoded, ride);
    });
  });
}
