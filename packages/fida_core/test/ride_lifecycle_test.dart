import 'package:fida_core/fida_core.dart';
import 'package:test/test.dart';

void main() {
  const policy = StandardRideTransitionPolicy();

  group('RideStatus', () {
    test('converts from wire value', () {
      expect(RideStatus.fromWire('driver_en_route'), RideStatus.driverEnRoute);
    });

    test('rejects unknown wire value', () {
      expect(() => RideStatus.fromWire('unknown'), throwsFormatException);
    });
  });

  group('StandardRideTransitionPolicy', () {
    test('allows a normal immediate transition', () {
      expect(
        policy.canTransition(
          from: RideStatus.searching,
          to: RideStatus.driverOffered,
        ),
        isTrue,
      );
    });

    test('rejects an impossible immediate transition', () {
      expect(
        policy.canTransition(from: RideStatus.draft, to: RideStatus.paid),
        isFalse,
      );
    });

    test('allows a reachable state after missed server events', () {
      expect(
        policy.canReach(
          from: RideStatus.searching,
          to: RideStatus.driverEnRoute,
        ),
        isTrue,
      );
    });

    test('does not allow a paid ride to progress again', () {
      expect(
        policy.canReach(from: RideStatus.paid, to: RideStatus.searching),
        isFalse,
      );
    });

    test('throws for an illegal transition', () {
      expect(
        () => policy.ensureTransitionAllowed(
          from: RideStatus.inProgress,
          to: RideStatus.cancelledByRider,
        ),
        throwsA(isA<InvalidRideTransition>()),
      );
    });
  });
}
