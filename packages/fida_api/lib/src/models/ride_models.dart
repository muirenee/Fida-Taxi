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
  enRoute('en_route'),
  arrived('arrived'),
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
      BackendTripStatus.enRoute => RideStatus.driverEnRoute,
      BackendTripStatus.arrived => RideStatus.driverArrived,
      BackendTripStatus.pickedUp => RideStatus.inProgress,
      BackendTripStatus.completed => RideStatus.completed,
      BackendTripStatus.cancelled => null,
    };
  }
}

enum DriverTripAction {
  enRoute('en_route'),
  arrive('arrive'),
  start('start'),
  complete('complete');

  const DriverTripAction(this.wireValue);

  final String wireValue;
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
    this.lifecycleStatus,
    this.revision = 0,
  });

  final String tripId;
  final BackendTripStatus status;
  final RideStatus? lifecycleStatus;
  final int revision;
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

  RideStatus? get domainStatus => lifecycleStatus ?? status.domainStatus;

  factory RideRequestResult.fromJson(Map<String, dynamic> json) {
    final bidding = _requiredMap(json['bidding'], 'bidding');
    final dispatch = _requiredMap(json['dispatch'], 'dispatch');

    return RideRequestResult(
      tripId: _requiredString(json['trip_id'], 'trip_id'),
      status: BackendTripStatus.fromWire(
        _requiredString(json['status'], 'status'),
      ),
      lifecycleStatus: _optionalRideStatus(json['lifecycle_status']),
      revision: _optionalInt(json['revision'], 'revision') ?? 0,
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

final class RideSnapshot {
  const RideSnapshot({
    required this.tripId,
    required this.riderId,
    required this.status,
    required this.revision,
    required this.vehicleType,
    required this.currency,
    required this.surgeMultiplier,
    required this.paymentMethod,
    required this.pickup,
    required this.dropoff,
    required this.createdAt,
    required this.updatedAt,
    this.driverId,
    this.lifecycleStatus,
    this.fareAmount,
    this.cancellationActor,
    this.cancellationReason,
  });

  final String tripId;
  final String riderId;
  final String? driverId;
  final BackendTripStatus status;
  final RideStatus? lifecycleStatus;
  final int revision;
  final VehicleType vehicleType;
  final String? fareAmount;
  final String currency;
  final String surgeMultiplier;
  final RidePaymentMethod paymentMethod;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final String? cancellationActor;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  RideStatus? get domainStatus {
    if (lifecycleStatus != null) return lifecycleStatus;
    if (status != BackendTripStatus.cancelled) return status.domainStatus;
    return switch (cancellationActor) {
      'rider' => RideStatus.cancelledByRider,
      'driver' => RideStatus.cancelledByDriver,
      _ => null,
    };
  }

  bool get isTerminal =>
      status == BackendTripStatus.completed ||
      status == BackendTripStatus.cancelled;

  bool get canCancel =>
      status == BackendTripStatus.created ||
      status == BackendTripStatus.matching ||
      status == BackendTripStatus.accepted ||
      status == BackendTripStatus.enRoute ||
      status == BackendTripStatus.arrived;

  factory RideSnapshot.fromJson(Map<String, dynamic> json) {
    final pickup = _requiredMap(json['pickup'], 'pickup');
    final dropoff = _requiredMap(json['dropoff'], 'dropoff');

    return RideSnapshot(
      tripId: _requiredString(json['trip_id'], 'trip_id'),
      riderId: _requiredString(json['rider_id'], 'rider_id'),
      driverId: _optionalString(json['driver_id'], 'driver_id'),
      status: BackendTripStatus.fromWire(
        _requiredString(json['status'], 'status'),
      ),
      lifecycleStatus: _optionalRideStatus(json['lifecycle_status']),
      revision: _requiredInt(json['revision'], 'revision'),
      vehicleType: VehicleType.fromWire(
        _requiredString(json['vehicle_type'], 'vehicle_type'),
      ),
      fareAmount: _optionalDecimalText(json['fare_amount'], 'fare_amount'),
      currency: _requiredString(json['currency'], 'currency').toUpperCase(),
      surgeMultiplier: _decimalText(
        json['surge_multiplier'],
        'surge_multiplier',
      ),
      paymentMethod: RidePaymentMethod.fromWire(
        _requiredString(json['payment_method'], 'payment_method'),
      ),
      pickup: GeoPoint(
        latitude: _requiredDouble(pickup['lat'], 'pickup.lat'),
        longitude: _requiredDouble(pickup['lng'], 'pickup.lng'),
      ),
      dropoff: GeoPoint(
        latitude: _requiredDouble(dropoff['lat'], 'dropoff.lat'),
        longitude: _requiredDouble(dropoff['lng'], 'dropoff.lng'),
      ),
      cancellationActor: _optionalString(
        json['cancellation_actor'],
        'cancellation_actor',
      ),
      cancellationReason: _optionalString(
        json['cancellation_reason'],
        'cancellation_reason',
      ),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
      updatedAt: _requiredDateTime(json['updated_at'], 'updated_at'),
    );
  }
}

final class DriverAvailabilityState {
  const DriverAvailabilityState({
    required this.driverId,
    required this.isOnline,
    required this.isAvailable,
    required this.presenceTtlSeconds,
    this.latitude,
    this.longitude,
  });

  final String driverId;
  final bool isOnline;
  final bool isAvailable;
  final int presenceTtlSeconds;
  final double? latitude;
  final double? longitude;

  factory DriverAvailabilityState.fromJson(Map<String, dynamic> json) {
    return DriverAvailabilityState(
      driverId: _requiredString(json['driver_id'], 'driver_id'),
      isOnline: _requiredBool(json['is_online'], 'is_online'),
      isAvailable: _requiredBool(json['is_available'], 'is_available'),
      presenceTtlSeconds: _requiredInt(
        json['presence_ttl_seconds'],
        'presence_ttl_seconds',
      ),
      latitude: _optionalDouble(json['latitude'], 'latitude'),
      longitude: _optionalDouble(json['longitude'], 'longitude'),
    );
  }
}

final class RideOfferBatch {
  const RideOfferBatch({
    required this.offers,
    required this.generatedAt,
  });

  final List<RideSnapshot> offers;
  final DateTime generatedAt;

  factory RideOfferBatch.fromJson(Map<String, dynamic> json) {
    final rawOffers = json['offers'];
    if (rawOffers is! List<Object?>) {
      throw const FormatException('offers must be an array.');
    }

    return RideOfferBatch(
      offers: rawOffers
          .map(
            (offer) => RideSnapshot.fromJson(
              _requiredMap(offer, 'offer'),
            ),
          )
          .toList(growable: false),
      generatedAt: _requiredDateTime(json['generated_at'], 'generated_at'),
    );
  }
}

RideStatus? _optionalRideStatus(Object? value) {
  if (value == null) return null;
  return RideStatus.fromWire(_requiredString(value, 'lifecycle_status'));
}

String _requiredString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$fieldName must be a string or null.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
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

int? _optionalInt(Object? value, String fieldName) {
  if (value == null) return null;
  return _requiredInt(value, fieldName);
}

double _requiredDouble(Object? value, String fieldName) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$fieldName must be numeric.');
  }
  return value.toDouble();
}

double? _optionalDouble(Object? value, String fieldName) {
  if (value == null) return null;
  return _requiredDouble(value, fieldName);
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

String? _optionalDecimalText(Object? value, String fieldName) {
  if (value == null) return null;
  return _decimalText(value, fieldName);
}

DateTime _requiredDateTime(Object? value, String fieldName) {
  if (value is! String) {
    throw FormatException('$fieldName must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$fieldName must be an ISO-8601 string.');
  }
  return parsed.toUtc();
}
