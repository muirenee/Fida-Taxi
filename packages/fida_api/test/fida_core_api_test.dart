import 'dart:convert';

import 'package:fida_api/fida_api.dart';
import 'package:fida_core/fida_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('FidaApiConfiguration', () {
    test('normalizes the base URL before resolving endpoints', () {
      final config = FidaApiConfiguration(
        baseUrl: 'https://api.example.test/api/v1',
      );

      expect(
        config.endpoint('/auth/phone/request').toString(),
        'https://api.example.test/api/v1/auth/phone/request',
      );
    });

    test('rejects non HTTP base URLs', () {
      expect(
        () => FidaApiConfiguration(baseUrl: 'file:///tmp/api'),
        throwsArgumentError,
      );
    });
  });

  group('FidaCoreApi', () {
    test('requests a phone login challenge', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/phone/request');
        expect(jsonDecode(request.body), <String, dynamic>{
          'phone': '+250788000001',
        });

        return http.Response(
          jsonEncode(<String, dynamic>{
            'accepted': true,
            'challenge_id': '0f44fd5c-c602-4b3f-9c48-c89a75aef571',
            'expires_in_seconds': 300,
            'dev_code': '123456',
          }),
          202,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final api = FidaCoreApi(
        configuration: FidaApiConfiguration(
          baseUrl: 'https://api.example.test/api/v1',
        ),
        client: client,
      );

      final result = await api.requestPhoneLogin('+250788000001');

      expect(result.accepted, isTrue);
      expect(result.canVerify, isTrue);
      expect(result.developmentCode, '123456');
    });

    test('parses a verified rider session', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/phone/verify');

        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': 'jwt-token',
            'token_type': 'Bearer',
            'expires_in_seconds': 900,
            'user_id': 'd79dd542-25f1-4a80-9722-454dc6a564cb',
            'driver_id': null,
            'role': 'rider',
          }),
          200,
        );
      });

      final api = FidaCoreApi(
        configuration: FidaApiConfiguration(
          baseUrl: 'https://api.example.test/api/v1',
        ),
        client: client,
      );

      final session = await api.verifyPhoneLogin(
        challengeId: '0f44fd5c-c602-4b3f-9c48-c89a75aef571',
        code: '123456',
      );

      expect(session.role, AuthRole.rider);
      expect(session.userId, 'd79dd542-25f1-4a80-9722-454dc6a564cb');
      expect(session.driverId, isNull);
    });

    test('uses the authenticated user id when requesting a ride', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/rides/request');
        expect(request.headers['authorization'], 'Bearer rider-jwt');

        final payload = Map<String, dynamic>.from(
          jsonDecode(request.body) as Map<Object?, Object?>,
        );
        expect(
          payload['rider_id'],
          'd79dd542-25f1-4a80-9722-454dc6a564cb',
        );
        expect(payload['vehicle_type'], 'taxi');
        expect(payload['payment_method'], 'cash');

        return http.Response(
          jsonEncode(<String, dynamic>{
            'trip_id': '408f895e-8232-48a8-a00e-7a5ea64f6d05',
            'status': 'matching',
            'vehicle_type': 'taxi',
            'payment_method': 'cash',
            'estimated_distance_meters': 8400,
            'estimated_fare': '8500.0000',
            'currency': 'RWF',
            'surge_multiplier': '1.0000',
            'bidding': <String, dynamic>{
              'state': 'broadcasted',
              'expires_in_seconds': 120,
            },
            'dispatch': <String, dynamic>{
              'radius_km': 5,
              'candidate_count': 3,
              'deferred': false,
            },
          }),
          201,
        );
      });

      final api = FidaCoreApi(
        configuration: FidaApiConfiguration(
          baseUrl: 'https://api.example.test/api/v1',
        ),
        client: client,
      );
      final session = AuthSession(
        accessToken: 'rider-jwt',
        tokenType: 'Bearer',
        expiresInSeconds: 900,
        userId: 'd79dd542-25f1-4a80-9722-454dc6a564cb',
        role: AuthRole.rider,
      );

      final result = await api.requestRide(
        session: session,
        request: RideRequest(
          pickup: GeoPoint(latitude: -1.9441, longitude: 30.0619),
          dropoff: GeoPoint(latitude: -1.9706, longitude: 30.1044),
          vehicleType: VehicleType.taxi,
        ),
      );

      expect(result.status, BackendTripStatus.matching);
      expect(result.domainStatus, RideStatus.searching);
      expect(result.dispatchCandidateCount, 3);
      expect(result.estimatedFareAmount, '8500.0000');
    });

    test('does not guess who cancelled a legacy backend trip', () {
      expect(BackendTripStatus.cancelled.domainStatus, isNull);
    });

    test('surfaces structured backend errors', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'statusCode': 401,
            'message': 'Invalid or expired access token',
            'error': 'Unauthorized',
          }),
          401,
        );
      });

      final api = FidaCoreApi(
        configuration: FidaApiConfiguration(
          baseUrl: 'https://api.example.test/api/v1',
        ),
        client: client,
      );

      await expectLater(
        api.verifyPhoneLogin(
          challengeId: '0f44fd5c-c602-4b3f-9c48-c89a75aef571',
          code: '000000',
        ),
        throwsA(
          isA<FidaApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.message,
                'message',
                'Invalid or expired access token',
              ),
        ),
      );
    });
  });
}
