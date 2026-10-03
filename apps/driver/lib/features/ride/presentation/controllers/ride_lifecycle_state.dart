import 'package:fida_core/fida_core.dart';
import 'package:flutter/foundation.dart';

@immutable
final class RideLifecycleState {
  const RideLifecycleState({
    this.ride,
    this.isSynchronizing = false,
    this.failureMessage,
  });

  const RideLifecycleState.initial()
    : ride = null,
      isSynchronizing = false,
      failureMessage = null;

  final Ride? ride;
  final bool isSynchronizing;
  final String? failureMessage;

  RideStatus get status => ride?.status ?? RideStatus.draft;
  int get revision => ride?.revision ?? -1;
  String? get rideId => ride?.id;
  bool get hasServerRide => ride != null;
  bool get isTerminal => ride?.isTerminal ?? false;

  RideLifecycleState copyWith({
    Ride? ride,
    bool? isSynchronizing,
    String? failureMessage,
    bool clearFailure = false,
  }) {
    return RideLifecycleState(
      ride: ride ?? this.ride,
      isSynchronizing: isSynchronizing ?? this.isSynchronizing,
      failureMessage: clearFailure
          ? null
          : failureMessage ?? this.failureMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RideLifecycleState &&
            other.ride == ride &&
            other.isSynchronizing == isSynchronizing &&
            other.failureMessage == failureMessage;
  }

  @override
  int get hashCode => Object.hash(ride, isSynchronizing, failureMessage);

  @override
  String toString() {
    return 'RideLifecycleState(rideId: $rideId, status: ${status.wireValue}, '
        'revision: $revision, isSynchronizing: $isSynchronizing)';
  }
}
