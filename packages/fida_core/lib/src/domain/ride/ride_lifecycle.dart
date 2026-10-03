import 'dart:collection';

enum RideStatus {
  draft('draft'),
  quoting('quoting'),
  searching('searching'),
  driverOffered('driver_offered'),
  driverAssigned('driver_assigned'),
  driverEnRoute('driver_en_route'),
  driverArrived('driver_arrived'),
  inProgress('in_progress'),
  completed('completed'),
  paymentPending('payment_pending'),
  paid('paid'),
  cancelledByRider('cancelled_by_rider'),
  cancelledByDriver('cancelled_by_driver'),
  noDriverFound('no_driver_found'),
  paymentFailed('payment_failed');

  const RideStatus(this.wireValue);

  final String wireValue;

  static RideStatus fromWire(String value) {
    for (final status in RideStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }

    throw FormatException(
      'Unknown ride status: "$value".',
    );
  }

  bool get isTerminal {
    switch (this) {
      case RideStatus.paid:
      case RideStatus.cancelledByRider:
      case RideStatus.cancelledByDriver:
      case RideStatus.noDriverFound:
        return true;
      case RideStatus.draft:
      case RideStatus.quoting:
      case RideStatus.searching:
      case RideStatus.driverOffered:
      case RideStatus.driverAssigned:
      case RideStatus.driverEnRoute:
      case RideStatus.driverArrived:
      case RideStatus.inProgress:
      case RideStatus.completed:
      case RideStatus.paymentPending:
      case RideStatus.paymentFailed:
        return false;
    }
  }

  bool get isCancelled {
    return this == RideStatus.cancelledByRider ||
        this == RideStatus.cancelledByDriver;
  }

  bool get isActiveTrip {
    switch (this) {
      case RideStatus.driverAssigned:
      case RideStatus.driverEnRoute:
      case RideStatus.driverArrived:
      case RideStatus.inProgress:
        return true;
      case RideStatus.draft:
      case RideStatus.quoting:
      case RideStatus.searching:
      case RideStatus.driverOffered:
      case RideStatus.completed:
      case RideStatus.paymentPending:
      case RideStatus.paid:
      case RideStatus.cancelledByRider:
      case RideStatus.cancelledByDriver:
      case RideStatus.noDriverFound:
      case RideStatus.paymentFailed:
        return false;
    }
  }
}

abstract interface class RideTransitionPolicy {
  bool canTransition({
    required RideStatus from,
    required RideStatus to,
  });

  bool canReach({
    required RideStatus from,
    required RideStatus to,
  });

  void ensureTransitionAllowed({
    required RideStatus from,
    required RideStatus to,
  });
}

final class StandardRideTransitionPolicy implements RideTransitionPolicy {
  const StandardRideTransitionPolicy();

  static const Map<RideStatus, Set<RideStatus>> _allowedTransitions =
      <RideStatus, Set<RideStatus>>{
    RideStatus.draft: <RideStatus>{
      RideStatus.quoting,
      RideStatus.cancelledByRider,
    },
    RideStatus.quoting: <RideStatus>{
      RideStatus.searching,
      RideStatus.cancelledByRider,
    },
    RideStatus.searching: <RideStatus>{
      RideStatus.driverOffered,
      RideStatus.noDriverFound,
      RideStatus.cancelledByRider,
    },
    RideStatus.driverOffered: <RideStatus>{
      RideStatus.searching,
      RideStatus.driverAssigned,
      RideStatus.noDriverFound,
      RideStatus.cancelledByRider,
    },
    RideStatus.driverAssigned: <RideStatus>{
      RideStatus.driverEnRoute,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
    },
    RideStatus.driverEnRoute: <RideStatus>{
      RideStatus.driverArrived,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
    },
    RideStatus.driverArrived: <RideStatus>{
      RideStatus.inProgress,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
    },
    RideStatus.inProgress: <RideStatus>{
      RideStatus.completed,
    },
    RideStatus.completed: <RideStatus>{
      RideStatus.paymentPending,
    },
    RideStatus.paymentPending: <RideStatus>{
      RideStatus.paid,
      RideStatus.paymentFailed,
    },
    RideStatus.paymentFailed: <RideStatus>{
      RideStatus.paymentPending,
    },
    RideStatus.paid: <RideStatus>{},
    RideStatus.cancelledByRider: <RideStatus>{},
    RideStatus.cancelledByDriver: <RideStatus>{},
    RideStatus.noDriverFound: <RideStatus>{},
  };

  @override
  bool canTransition({
    required RideStatus from,
    required RideStatus to,
  }) {
    if (from == to) {
      return true;
    }

    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  @override
  bool canReach({
    required RideStatus from,
    required RideStatus to,
  }) {
    if (from == to) {
      return true;
    }

    final visited = <RideStatus>{};
    final queue = Queue<RideStatus>()..add(from);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      if (!visited.add(current)) {
        continue;
      }

      final nextStates =
          _allowedTransitions[current] ?? const <RideStatus>{};

      for (final next in nextStates) {
        if (next == to) {
          return true;
        }

        if (!visited.contains(next)) {
          queue.add(next);
        }
      }
    }

    return false;
  }

  @override
  void ensureTransitionAllowed({
    required RideStatus from,
    required RideStatus to,
  }) {
    if (!canTransition(from: from, to: to)) {
      throw InvalidRideTransition(
        from: from,
        to: to,
      );
    }
  }
}

final class InvalidRideTransition implements Exception {
  const InvalidRideTransition({
    required this.from,
    required this.to,
  });

  final RideStatus from;
  final RideStatus to;

  @override
  String toString() {
    return 'InvalidRideTransition(' +
        from.wireValue +
        ' -> ' +
        to.wireValue +
        ')';
  }
}
