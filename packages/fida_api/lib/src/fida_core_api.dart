import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_configuration.dart';
import 'api_exception.dart';
import 'models/auth_models.dart';
import 'models/ride_models.dart';

final class FidaCoreApi {
  FidaCoreApi({required this.configuration, http.Client? client})
    : _client = client ?? http.Client();

  final FidaApiConfiguration configuration;
  final http.Client _client;

  Future<PhoneLoginChallenge> requestPhoneLogin(String phone) async {
    final json = await _post(
      'auth/phone/request',
      body: <String, dynamic>{'phone': phone.trim()},
    );

    return PhoneLoginChallenge.fromJson(json);
  }

  Future<AuthSession> verifyPhoneLogin({
    required String challengeId,
    required String code,
  }) async {
    final json = await _post(
      'auth/phone/verify',
      body: <String, dynamic>{
        'challenge_id': challengeId.trim(),
        'code': code.trim(),
      },
    );

    return AuthSession.fromJson(json);
  }

  Future<RegisteredRider> registerRider(
    RiderRegistration registration, {
    Map<String, String> attestationHeaders = const <String, String>{},
  }) async {
    final json = await _post(
      'auth/register/rider',
      body: registration.toJson(),
      extraHeaders: attestationHeaders,
    );

    return RegisteredRider.fromJson(json);
  }

  Future<RegisteredDriver> registerDriver(
    DriverRegistration registration, {
    Map<String, String> attestationHeaders = const <String, String>{},
  }) async {
    final json = await _post(
      'auth/register/driver',
      body: registration.toJson(),
      extraHeaders: attestationHeaders,
    );

    return RegisteredDriver.fromJson(json);
  }

  Future<RideRequestResult> requestRide({
    required AuthSession session,
    required RideRequest request,
    Map<String, String> attestationHeaders = const <String, String>{},
  }) async {
    _requireRole(session, AuthRole.rider);

    final json = await _post(
      'rides/request',
      body: request.toJson(riderId: session.userId),
      accessToken: session.accessToken,
      extraHeaders: attestationHeaders,
    );

    return RideRequestResult.fromJson(json);
  }

  Future<RideSnapshot?> getActiveRiderTrip(AuthSession session) async {
    _requireRole(session, AuthRole.rider);
    final json = await _get(
      'rides/rider/active',
      accessToken: session.accessToken,
    );
    return _optionalTrip(json['trip']);
  }

  Future<RideSnapshot> getTrip({
    required AuthSession session,
    required String tripId,
  }) async {
    final json = await _get(
      'rides/' + Uri.encodeComponent(tripId),
      accessToken: session.accessToken,
    );
    return RideSnapshot.fromJson(json);
  }

  Future<RideSnapshot> cancelTrip({
    required AuthSession session,
    required String tripId,
    String? reason,
  }) async {
    final json = await _post(
      'rides/' + Uri.encodeComponent(tripId) + '/cancel',
      body: <String, dynamic>{
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      accessToken: session.accessToken,
    );
    return RideSnapshot.fromJson(json);
  }

  Future<DriverAvailabilityState> setDriverAvailability({
    required AuthSession session,
    required bool isAvailable,
    double? latitude,
    double? longitude,
  }) async {
    _requireRole(session, AuthRole.driver);

    final json = await _post(
      'rides/driver/availability',
      body: <String, dynamic>{
        'is_available': isAvailable,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      accessToken: session.accessToken,
    );

    return DriverAvailabilityState.fromJson(json);
  }

  Future<RideOfferBatch> getDriverOffers(AuthSession session) async {
    _requireRole(session, AuthRole.driver);
    final json = await _get(
      'rides/driver/offers',
      accessToken: session.accessToken,
    );
    return RideOfferBatch.fromJson(json);
  }

  Future<RideSnapshot?> getActiveDriverTrip(AuthSession session) async {
    _requireRole(session, AuthRole.driver);
    final json = await _get(
      'rides/driver/active',
      accessToken: session.accessToken,
    );
    return _optionalTrip(json['trip']);
  }

  Future<RideSnapshot> acceptTrip({
    required AuthSession session,
    required String tripId,
  }) async {
    _requireRole(session, AuthRole.driver);
    final json = await _post(
      'rides/' + Uri.encodeComponent(tripId) + '/accept',
      body: const <String, dynamic>{},
      accessToken: session.accessToken,
    );
    return RideSnapshot.fromJson(json);
  }

  Future<RideSnapshot> applyDriverAction({
    required AuthSession session,
    required String tripId,
    required DriverTripAction action,
  }) async {
    _requireRole(session, AuthRole.driver);
    final json = await _post(
      'rides/' + Uri.encodeComponent(tripId) + '/action',
      body: <String, dynamic>{'action': action.wireValue},
      accessToken: session.accessToken,
    );
    return RideSnapshot.fromJson(json);
  }

  Future<TelemetrySession> createTelemetrySession({
    required AuthSession session,
    Map<String, String> attestationHeaders = const <String, String>{},
  }) async {
    _requireRole(session, AuthRole.driver);

    final json = await _post(
      'auth/telemetry-session',
      body: const <String, dynamic>{},
      accessToken: session.accessToken,
      extraHeaders: attestationHeaders,
    );

    return TelemetrySession.fromJson(json);
  }

  void close() {
    _client.close();
  }

  void _requireRole(AuthSession session, AuthRole role) {
    if (session.role != role) {
      throw ArgumentError('A ${role.wireValue} session is required.');
    }
  }

  RideSnapshot? _optionalTrip(Object? value) {
    if (value == null) return null;
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('trip must be an object or null.');
    }
    return RideSnapshot.fromJson(Map<String, dynamic>.from(value));
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String? accessToken,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final headers = <String, String>{
      'accept': 'application/json',
      ...extraHeaders,
      if (accessToken != null) 'authorization': 'Bearer $accessToken',
    };

    late final http.Response response;
    try {
      response = await _client.get(
        configuration.endpoint(path),
        headers: headers,
      );
    } on http.ClientException catch (error) {
      throw FidaApiException(
        message: 'Unable to reach the Fida Ride API.',
        details: error.message,
      );
    }

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    String? accessToken,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final headers = <String, String>{
      'accept': 'application/json',
      'content-type': 'application/json',
      ...extraHeaders,
      if (accessToken != null) 'authorization': 'Bearer $accessToken',
    };

    late final http.Response response;
    try {
      response = await _client.post(
        configuration.endpoint(path),
        headers: headers,
        body: jsonEncode(body),
      );
    } on http.ClientException catch (error) {
      throw FidaApiException(
        message: 'Unable to reach the Fida Ride API.',
        details: error.message,
      );
    }

    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = _decodeObject(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FidaApiException(
        statusCode: response.statusCode,
        message: _errorMessage(decoded),
        error: decoded['error'] is String ? decoded['error'] as String : null,
        details: decoded,
      );
    }

    return decoded;
  }

  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw FidaApiException(
        message: 'Fida Ride API returned invalid JSON.',
        details: error.message,
      );
    }

    if (decoded is! Map<Object?, Object?>) {
      throw const FidaApiException(
        message: 'Fida Ride API returned an unexpected response shape.',
      );
    }

    return Map<String, dynamic>.from(decoded);
  }

  String _errorMessage(Map<String, dynamic> json) {
    final message = json['message'];

    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    if (message is List<Object?> && message.isNotEmpty) {
      return message.whereType<String>().join('; ');
    }

    return 'Fida Ride API request failed.';
  }
}
