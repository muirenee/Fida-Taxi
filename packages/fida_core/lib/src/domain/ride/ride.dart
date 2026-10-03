import '../common/geo_point.dart';
import '../common/money.dart';
import 'ride_lifecycle.dart';
import 'route_summary.dart';
import 'vehicle_type.dart';

final class Ride {
  Ride({
    required String id,
    required String riderId,
    required this.status,
    required this.pickup,
    required this.dropoff,
    required this.vehicleType,
    required int revision,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? assignedDriverId,
    this.quotedFare,
    this.finalFare,
    this.route,
  })  : id = _requiredIdentifier(id, 'id'),
        riderId = _requiredIdentifier(riderId, 'riderId'),
        assignedDriverId = assignedDriverId == null
            ? null
            : _requiredIdentifier(assignedDriverId, 'assignedDriverId'),
        revision = _validRevision(revision),
        createdAt = createdAt.toUtc(),
        updatedAt = updatedAt.toUtc() {
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError(
        'updatedAt cannot be before createdAt.',
      );
    }

    if (quotedFare != null &&
        finalFare != null &&
        quotedFare!.currency != finalFare!.currency) {
      throw ArgumentError(
        'Quoted fare and final fare must use the same currency.',
      );
    }
  }

  final String id;
  final String riderId;
  final String? assignedDriverId;
  final RideStatus status;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final VehicleType vehicleType;
  final Money? quotedFare;
  final Money? finalFare;
  final RouteSummary? route;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal => status.isTerminal;
  bool get isActive => status.isActiveTrip;
  bool get hasAssignedDriver => assignedDriverId != null;

  Ride copyWith({
    String? id,
    String? riderId,
    String? assignedDriverId,
    RideStatus? status,
    GeoPoint? pickup,
    GeoPoint? dropoff,
    VehicleType? vehicleType,
    Money? quotedFare,
    Money? finalFare,
    RouteSummary? route,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearAssignedDriver = false,
    bool clearQuotedFare = false,
    bool clearFinalFare = false,
    bool clearRoute = false,
  }) {
    return Ride(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      assignedDriverId: clearAssignedDriver
          ? null
          : assignedDriverId ?? this.assignedDriverId,
      status: status ?? this.status,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      vehicleType: vehicleType ?? this.vehicleType,
      quotedFare:
          clearQuotedFare ? null : quotedFare ?? this.quotedFare,
      finalFare: clearFinalFare ? null : finalFare ?? this.finalFare,
      route: clearRoute ? null : route ?? this.route,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'rider_id': riderId,
      'assigned_driver_id': assignedDriverId,
      'status': status.wireValue,
      'pickup': pickup.toJson(),
      'dropoff': dropoff.toJson(),
      'vehicle_type': vehicleType.wireValue,
      'quoted_fare': quotedFare?.toJson(),
      'final_fare': finalFare?.toJson(),
      'route': route?.toJson(),
      'revision': revision,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Ride.fromJson(Map<String, dynamic> json) {
    final quotedFareValue = json['quoted_fare'];
    final finalFareValue = json['final_fare'];
    final routeValue = json['route'];

    return Ride(
      id: _requiredString(json['id'], 'id'),
      riderId: _requiredString(json['rider_id'], 'rider_id'),
      assignedDriverId: _optionalString(
        json['assigned_driver_id'],
        'assigned_driver_id',
      ),
      status: RideStatus.fromWire(
        _requiredString(json['status'], 'status'),
      ),
      pickup: GeoPoint.fromJson(
        _requiredMap(json['pickup'], 'pickup'),
      ),
      dropoff: GeoPoint.fromJson(
        _requiredMap(json['dropoff'], 'dropoff'),
      ),
      vehicleType: VehicleType.fromWire(
        _requiredString(json['vehicle_type'], 'vehicle_type'),
      ),
      quotedFare: quotedFareValue == null
          ? null
          : Money.fromJson(
              _requiredMap(quotedFareValue, 'quoted_fare'),
            ),
      finalFare: finalFareValue == null
          ? null
          : Money.fromJson(
              _requiredMap(finalFareValue, 'final_fare'),
            ),
      route: routeValue == null
          ? null
          : RouteSummary.fromJson(
              _requiredMap(routeValue, 'route'),
            ),
      revision: _requiredInt(json['revision'], 'revision'),
      createdAt: _requiredDateTime(
        json['created_at'],
        'created_at',
      ),
      updatedAt: _requiredDateTime(
        json['updated_at'],
        'updated_at',
      ),
    );
  }

  static String _requiredIdentifier(
    String value,
    String fieldName,
  ) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName cannot be empty.',
      );
    }

    return normalized;
  }

  static int _validRevision(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'revision',
        'Revision cannot be negative.',
      );
    }

    return value;
  }

  static String _requiredString(
    Object? value,
    String fieldName,
  ) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        '$fieldName must be a non-empty string.',
      );
    }

    return value;
  }

  static String? _optionalString(
    Object? value,
    String fieldName,
  ) {
    if (value == null) {
      return null;
    }

    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        '$fieldName must be a non-empty string or null.',
      );
    }

    return value;
  }

  static int _requiredInt(
    Object? value,
    String fieldName,
  ) {
    if (value is! num) {
      throw FormatException(
        '$fieldName must be numeric.',
      );
    }

    return value.toInt();
  }

  static Map<String, dynamic> _requiredMap(
    Object? value,
    String fieldName,
  ) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException(
        '$fieldName must be an object.',
      );
    }

    return Map<String, dynamic>.from(value);
  }

  static DateTime _requiredDateTime(
    Object? value,
    String fieldName,
  ) {
    if (value is! String) {
      throw FormatException(
        '$fieldName must be an ISO-8601 string.',
      );
    }

    final parsed = DateTime.tryParse(value);

    if (parsed == null) {
      throw FormatException(
        '$fieldName is not a valid ISO-8601 date.',
      );
    }

    return parsed.toUtc();
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Ride &&
            other.id == id &&
            other.riderId == riderId &&
            other.assignedDriverId == assignedDriverId &&
            other.status == status &&
            other.pickup == pickup &&
            other.dropoff == dropoff &&
            other.vehicleType == vehicleType &&
            other.quotedFare == quotedFare &&
            other.finalFare == finalFare &&
            other.route == route &&
            other.revision == revision &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        riderId,
        assignedDriverId,
        status,
        pickup,
        dropoff,
        vehicleType,
        quotedFare,
        finalFare,
        route,
        revision,
        createdAt,
        updatedAt,
      );

  @override
  String toString() {
    return 'Ride(id: $id, riderId: $riderId, driverId: $assignedDriverId, '
        'status: ${status.wireValue}, revision: $revision)';
  }
}
