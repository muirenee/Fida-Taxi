import 'package:fida_core/fida_core.dart';

enum RidePaymentMethod {
  cash('cash'),
  card('card'),
  wallet('wallet');

  const RidePaymentMethod(this.wireValue);

  final String wireValue;

  static RidePaymentMethod fromWire(String value) {
    for (final method in RidePaymentMethod.values) {
      if (method.wireValue == value) {
        return method;
      }
    }

    throw FormatException('Unknown payment method: "$value".');
  }
}

enum BackendTripStatus {
  created('created'),
  matching('matching'),
  accepted('accepted'),
  pickedUp('picked_up'),
  completed('completed'),
  cancelled('cancelled');

  const BackendTripStatus(this.wireValue);

  final String wireValue;

  static BackendTripStatus fromWire(String value) {
    for (final status in BackendTripStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }

    throw FormatException('Unknown backend trip status: "$value".');
  }

  RideStatus? get domainStatus {
    return switch (this) {
      BackendTripStatus.created => RideStatus.quoting,
      BackendTripStatus.matching => RideStatus.searching,
      BackendTripStatus.accepted => RideStatus.driverAssigned,
      BackendTripStatus.pickedUp => RideStatus.inProgress,
      BackendTripStatus.completed => RideStatus.completed,
      BackendTripStatus.cancelled => null,
    };
  }
}

final class RideRequest {
  const RideRequest({
    required this.pickup,
    required this.dropoff,
    required this.vehicleType,
    this.paymentMethod = RidePaymentMethod.cash,
  });

  final GeoPoint pickup;
  final GeoPoint dropoff;
  final VehicleType vehicleType;
  final RidePaymentMethod paymentMethod;

  Map<String, dynamic> toJson({required String riderId}) {
    return <String, dynamic>{
      'rider_id': riderId,
      'pickup_lat': pickup.latitude,
      'pickup_lng': pickup.longitude,
      'dropoff_lat': dropoff.latitude,
      'dropoff_lng': dropoff.longitude,
      'vehicle_type': vehicleType.wireValue,
      'payment_method': paymentMethod.wireValue,
    };
  }
}

final class RideRequestResult {
  const RideRequestResult({
    required this.tripId,
    required this.status,
    required this.vehicleType,
    required this.paymentMethod,
    required this.estimatedDistanceMeters,
    required this.estimatedFareAmount,
    required this.currency,
    required this.surgeMultiplier,
    required this.biddingState,
    required this.biddingExpiresInSeconds,
    required this.dispatchRadiusKm,
    required this.dispatchCandidateCount,
    required this.dispatchDeferred,
  });

  final String tripId;
  final BackendTripStatus status;
  final VehicleType vehicleType;
  final RidePaymentMethod paymentMethod;
  final int estimatedDistanceMeters;
  final String estimatedFareAmount;
  final String currency;
  final String surgeMultiplier;
  final String biddingState;
  final int biddingExpiresInSeconds;
  final double dispatchRadiusKm;
  final int dispatchCandidateCount;
  final bool dispatchDeferred;

  RideStatus? get domainStatus => status.domainStatus;

  factory RideRequestResult.fromJson(Map<String, dynamic> json) {
    final bidding = _requiredMap(json['bidding'], 'bidding');
    final dispatch = _requiredMap(json['dispatch'], 'dispatch');

    return RideRequestResult(
      tripId: _requiredString(json['trip_id'], 'trip_id'),
      status: BackendTripStatus.fromWire(
        _requiredString(json['status'], 'status'),
      ),
      vehicleType: VehicleType.fromWire(
        _requiredString(json['vehicle_type'], 'vehicle_type'),
      ),
      paymentMethod: RidePaymentMethod.fromWire(
        _requiredString(json['payment_method'], 'payment_method'),
      ),
      estimatedDistanceMeters: _requiredInt(
        json['estimated_distance_meters'],
        'estimated_distance_meters',
      ),
      estimatedFareAmount: _decimalText(
        json['estimated_fare'],
        'estimated_fare',
      ),
      currency: _requiredString(json['currency'], 'currency').toUpperCase(),
      surgeMultiplier: _decimalText(
        json['surge_multiplier'],
        'surge_multiplier',
      ),
      biddingState: _requiredString(bidding['state'], 'bidding.state'),
      biddingExpiresInSeconds: _requiredInt(
        bidding['expires_in_seconds'],
        'bidding.expires_in_seconds',
      ),
      dispatchRadiusKm: _requiredDouble(
        dispatch['radius_km'],
        'dispatch.radius_km',
      ),
      dispatchCandidateCount: _requiredInt(
        dispatch['candidate_count'],
        'dispatch.candidate_count',
      ),
      dispatchDeferred: _requiredBool(
        dispatch['deferred'],
        'dispatch.deferred',
      ),
    );
  }
}

String _requiredString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string.');
  }
  return value;
}

Map<String, dynamic> _requiredMap(Object? value, String fieldName) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$fieldName must be an object.');
  }
  return Map<String, dynamic>.from(value);
}

int _requiredInt(Object? value, String fieldName) {
  if (value is! num || value != value.roundToDouble()) {
    throw FormatException('$fieldName must be an integer.');
  }
  return value.toInt();
}

double _requiredDouble(Object? value, String fieldName) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$fieldName must be numeric.');
  }
  return value.toDouble();
}

bool _requiredBool(Object? value, String fieldName) {
  if (value is! bool) {
    throw FormatException('$fieldName must be a boolean.');
  }
  return value;
}

String _decimalText(Object? value, String fieldName) {
  if (value is String) {
    final parsed = num.tryParse(value);
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$fieldName must be numeric.');
    }
    return value;
  }

  if (value is num && value.isFinite) {
    return value.toString();
  }

  throw FormatException('$fieldName must be numeric.');
}
