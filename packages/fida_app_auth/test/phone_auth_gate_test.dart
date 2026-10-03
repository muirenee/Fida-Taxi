import 'package:fida_api/fida_api.dart';
import 'package:fida_app_auth/fida_app_auth.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders rider phone authentication fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FidaTheme.light,
        home: PhoneAuthGate(
          appName: 'Fida Taxi',
          expectedRole: AuthRole.rider,
          initialBaseUrl: 'https://api.example.test/api/v1',
          authenticatedBuilder: (context, session, api, signOut) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(find.text('Sign in to ride'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('API server (testing)'), findsOneWidget);
  });

  testWidgets('renders driver-specific heading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FidaTheme.light,
        home: PhoneAuthGate(
          appName: 'Fida Taxi Driver',
          expectedRole: AuthRole.driver,
          initialBaseUrl: 'https://api.example.test/api/v1',
          authenticatedBuilder: (context, session, api, signOut) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(find.text('Driver sign in'), findsOneWidget);
  });
}
