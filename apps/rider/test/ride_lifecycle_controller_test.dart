import 'package:fida_core/fida_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fida_taxi_rider/features/ride/presentation/controllers/ride_lifecycle_controller.dart';

void main() {
  Ride buildRide({
    required RideStatus status,
    required int revision,
    String? driverId,
  }) {
    final timestamp = DateTime.utc(2026, 10, 3, 9);

    return Ride(
      id: 'ride_001',
      riderId: 'rider_001',
      assignedDriverId: driverId,
      status: status,
      pickup: GeoPoint(latitude: -1.9441, longitude: 30.0619),
      dropoff: GeoPoint(latitude: -1.9706, longitude: 30.1044),
      vehicleType: VehicleType.taxi,
      quotedFare: Money(minorUnits: 7000, currency: 'RWF'),
      revision: revision,
      createdAt: timestamp,
      updatedAt: timestamp.add(Duration(seconds: revision)),
    );
  }

  test('starts in local draft state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(rideLifecycleControllerProvider);

    expect(state.status, RideStatus.draft);
    expect(state.hasServerRide, isFalse);
  });

  test('applies an authoritative ride', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(rideLifecycleControllerProvider.notifier);

    controller.applyAuthoritativeRide(
      buildRide(status: RideStatus.searching, revision: 1),
    );

    final state = container.read(rideLifecycleControllerProvider);

    expect(state.status, RideStatus.searching);
    expect(state.revision, 1);
  });

  test('ignores stale authoritative events', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(rideLifecycleControllerProvider.notifier);

    controller.applyAuthoritativeRide(
      buildRide(status: RideStatus.searching, revision: 5),
    );

    controller.applyAuthoritativeRide(
      buildRide(status: RideStatus.quoting, revision: 4),
    );

    final state = container.read(rideLifecycleControllerProvider);

    expect(state.status, RideStatus.searching);
    expect(state.revision, 5);
  });

  test('allows skipped server states after reconnect', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(rideLifecycleControllerProvider.notifier);

    controller.applyAuthoritativeRide(
      buildRide(status: RideStatus.searching, revision: 2),
    );

    controller.applyAuthoritativeRide(
      buildRide(
        status: RideStatus.driverEnRoute,
        revision: 5,
        driverId: 'driver_001',
      ),
    );

    expect(
      container.read(rideLifecycleControllerProvider).status,
      RideStatus.driverEnRoute,
    );
  });
}
