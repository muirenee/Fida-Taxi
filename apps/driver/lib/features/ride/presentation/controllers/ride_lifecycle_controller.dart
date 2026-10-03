import 'package:fida_core/fida_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ride_lifecycle_state.dart';

final driverRideLifecycleControllerProvider =
    NotifierProvider<DriverRideLifecycleController, RideLifecycleState>(
  DriverRideLifecycleController.new,
);

final class DriverRideLifecycleController extends Notifier<RideLifecycleState> {
  static const RideTransitionPolicy _transitionPolicy =
      StandardRideTransitionPolicy();

  @override
  RideLifecycleState build() {
    return const RideLifecycleState.initial();
  }

  void startLocalDraft() {
    state = const RideLifecycleState.initial();
  }

  void markSynchronizing() {
    state = state.copyWith(
      isSynchronizing: true,
      clearFailure: true,
    );
  }

  void applyAuthoritativeRide(Ride ride) {
    final currentRide = state.ride;

    if (currentRide != null && currentRide.id != ride.id) {
      return;
    }

    if (currentRide != null) {
      if (ride.revision <= currentRide.revision) {
        return;
      }

      final isReachable = _transitionPolicy.canReach(
        from: currentRide.status,
        to: ride.status,
      );

      if (!isReachable) {
        throw InvalidRideTransition(
          from: currentRide.status,
          to: ride.status,
        );
      }
    }

    state = RideLifecycleState(
      ride: ride,
      isSynchronizing: false,
    );
  }

  void reportFailure(String message) {
    final normalized = message.trim();

    state = state.copyWith(
      isSynchronizing: false,
      failureMessage: normalized.isEmpty
          ? 'An unexpected ride operation error occurred.'
          : normalized,
    );
  }

  void clearFailure() {
    state = state.copyWith(
      clearFailure: true,
    );
  }

  void reset() {
    state = const RideLifecycleState.initial();
  }
}
