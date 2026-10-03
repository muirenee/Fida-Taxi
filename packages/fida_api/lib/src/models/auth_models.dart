import 'package:fida_core/fida_core.dart';

enum AuthRole {
  rider('rider'),
  driver('driver');

  const AuthRole(this.wireValue);

  final String wireValue;

  static AuthRole fromWire(String value) {
    for (final role in AuthRole.values) {
      if (role.wireValue == value) {
        return role;
      }
    }

    throw FormatException('Unknown auth role: "$value".');
  }
}

final class PhoneLoginChallenge {
  const PhoneLoginChallenge({
    required this.accepted,
    this.challengeId,
    this.expiresInSeconds,
    this.developmentCode,
  });

  final bool accepted;
  final String? challengeId;
  final int? expiresInSeconds;
  final String? developmentCode;

  bool get canVerify => challengeId != null;

  factory PhoneLoginChallenge.fromJson(Map<String, dynamic> json) {
    return PhoneLoginChallenge(
      accepted: _requiredBool(json['accepted'], 'accepted'),
      challengeId: _optionalString(json['challenge_id'], 'challenge_id'),
      expiresInSeconds: _optionalInt(
        json['expires_in_seconds'],
        'expires_in_seconds',
      ),
      developmentCode: _optionalString(json['dev_code'], 'dev_code'),
    );
  }
}

final class AuthSession {
  AuthSession({
    required String accessToken,
    required String tokenType,
    required this.expiresInSeconds,
    required String userId,
    required this.role,
    String? driverId,
  }) : accessToken = _requiredIdentifier(accessToken, 'accessToken'),
       tokenType = _requiredIdentifier(tokenType, 'tokenType'),
       userId = _requiredIdentifier(userId, 'userId'),
       driverId = driverId == null
           ? null
           : _requiredIdentifier(driverId, 'driverId') {
    if (expiresInSeconds <= 0) {
      throw ArgumentError.value(
        expiresInSeconds,
        'expiresInSeconds',
        'Token lifetime must be positive.',
      );
    }

    if (role == AuthRole.driver && this.driverId == null) {
      throw ArgumentError('Driver sessions require driverId.');
    }
  }

  final String accessToken;
  final String tokenType;
  final int expiresInSeconds;
  final String userId;
  final String? driverId;
  final AuthRole role;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: _requiredString(json['access_token'], 'access_token'),
      tokenType: _requiredString(json['token_type'], 'token_type'),
      expiresInSeconds: _requiredInt(
        json['expires_in_seconds'],
        'expires_in_seconds',
      ),
      userId: _requiredString(json['user_id'], 'user_id'),
      driverId: _optionalString(json['driver_id'], 'driver_id'),
      role: AuthRole.fromWire(_requiredString(json['role'], 'role')),
    );
  }
}

final class RiderRegistration {
  RiderRegistration({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
  }) : firstName = _requiredIdentifier(firstName, 'firstName'),
       lastName = _requiredIdentifier(lastName, 'lastName'),
       phone = _requiredIdentifier(phone, 'phone'),
       email = _optionalNormalized(email);

  final String firstName;
  final String lastName;
  final String phone;
  final String? email;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      if (email != null) 'email': email,
    };
  }
}

final class DriverRegistration {
  DriverRegistration({
    required String firstName,
    required String lastName,
    required String phone,
    required this.vehicleType,
    required String licensePlate,
    String? email,
  }) : firstName = _requiredIdentifier(firstName, 'firstName'),
       lastName = _requiredIdentifier(lastName, 'lastName'),
       phone = _requiredIdentifier(phone, 'phone'),
       licensePlate = _requiredIdentifier(licensePlate, 'licensePlate'),
       email = _optionalNormalized(email);

  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final VehicleType vehicleType;
  final String licensePlate;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      if (email != null) 'email': email,
      'vehicle_type': vehicleType.wireValue,
      'license_plate': licensePlate,
    };
  }
}

final class RegisteredRider {
  const RegisteredRider({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.status,
    this.email,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final String status;

  factory RegisteredRider.fromJson(Map<String, dynamic> json) {
    return RegisteredRider(
      id: _requiredString(json['id'], 'id'),
      firstName: _requiredString(json['first_name'], 'first_name'),
      lastName: _requiredString(json['last_name'], 'last_name'),
      phone: _requiredString(json['phone'], 'phone'),
      email: _optionalString(json['email'], 'email'),
      status: _requiredString(json['status'], 'status'),
    );
  }
}

final class RegisteredDriver {
  const RegisteredDriver({
    required this.userId,
    required this.driverId,
    required this.phone,
    required this.vehicleType,
    required this.licensePlate,
    required this.verificationStatus,
  });

  final String userId;
  final String driverId;
  final String phone;
  final VehicleType vehicleType;
  final String licensePlate;
  final String verificationStatus;

  factory RegisteredDriver.fromJson(Map<String, dynamic> json) {
    return RegisteredDriver(
      userId: _requiredString(json['user_id'], 'user_id'),
      driverId: _requiredString(json['driver_id'], 'driver_id'),
      phone: _requiredString(json['phone'], 'phone'),
      vehicleType: VehicleType.fromWire(
        _requiredString(json['vehicle_type'], 'vehicle_type'),
      ),
      licensePlate: _requiredString(json['license_plate'], 'license_plate'),
      verificationStatus: _requiredString(
        json['verification_status'],
        'verification_status',
      ),
    );
  }
}

final class TelemetrySession {
  const TelemetrySession({
    required this.sessionId,
    required this.sessionKey,
    required this.expiresAt,
  });

  final String sessionId;
  final String sessionKey;
  final DateTime expiresAt;

  factory TelemetrySession.fromJson(Map<String, dynamic> json) {
    final expiresRaw = _requiredString(json['expires_at'], 'expires_at');
    final expiresAt = DateTime.tryParse(expiresRaw);

    if (expiresAt == null) {
      throw const FormatException('expires_at must be an ISO-8601 timestamp.');
    }

    return TelemetrySession(
      sessionId: _requiredString(json['session_id'], 'session_id'),
      sessionKey: _requiredString(json['session_key'], 'session_key'),
      expiresAt: expiresAt.toUtc(),
    );
  }
}

String _requiredIdentifier(String value, String fieldName) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, fieldName, '$fieldName cannot be empty.');
  }
  return normalized;
}

String? _optionalNormalized(String? value) {
  if (value == null) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _requiredString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string or null.');
  }
  return value;
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

bool _requiredBool(Object? value, String fieldName) {
  if (value is! bool) {
    throw FormatException('$fieldName must be a boolean.');
  }
  return value;
}
