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
    if (session.role != AuthRole.rider) {
      throw ArgumentError('A rider session is required to request a ride.');
    }

    final json = await _post(
      'rides/request',
      body: request.toJson(riderId: session.userId),
      accessToken: session.accessToken,
      extraHeaders: attestationHeaders,
    );

    return RideRequestResult.fromJson(json);
  }

  Future<TelemetrySession> createTelemetrySession({
    required AuthSession session,
    Map<String, String> attestationHeaders = const <String, String>{},
  }) async {
    if (session.role != AuthRole.driver || session.driverId == null) {
      throw ArgumentError(
        'A driver session is required to create a telemetry session.',
      );
    }

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
