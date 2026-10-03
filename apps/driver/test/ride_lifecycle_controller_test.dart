import 'package:fida_core/fida_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fida_taxi_driver/features/ride/presentation/controllers/ride_lifecycle_controller.dart';

void main() {
  Ride buildRide({
    required RideStatus status,
    required int revision,
  }) {
    final timestamp = DateTime.utc(2026, 10, 3, 9);

    return Ride(
      id: 'ride_001',
      riderId: 'rider_001',
      assignedDriverId: 'driver_001',
      status: status,
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
        minorUnits: 7000,
        currency: 'RWF',
      ),
      revision: revision,
      createdAt: timestamp,
      updatedAt: timestamp.add(Duration(seconds: revision)),
    );
  }

  test('applies valid driver lifecycle progression', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      driverRideLifecycleControllerProvider.notifier,
    );

    controller.applyAuthoritativeRide(
      buildRide(
        status: RideStatus.driverAssigned,
        revision: 4,
      ),
    );

    controller.applyAuthoritativeRide(
      buildRide(
        status: RideStatus.driverEnRoute,
        revision: 5,
      ),
    );

    final state = container.read(
      driverRideLifecycleControllerProvider,
    );

    expect(state.status, RideStatus.driverEnRoute);
    expect(state.revision, 5);
  });

  test('rejects an impossible backward state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      driverRideLifecycleControllerProvider.notifier,
    );

    controller.applyAuthoritativeRide(
      buildRide(
        status: RideStatus.inProgress,
        revision: 7,
      ),
    );

    expect(
      () => controller.applyAuthoritativeRide(
        buildRide(
          status: RideStatus.driverArrived,
          revision: 8,
        ),
      ),
      throwsA(isA<InvalidRideTransition>()),
    );
  });
}
