import 'package:fida_api/fida_api.dart';
import 'package:fida_app_auth/fida_app_auth.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildGate(AuthRole role) {
    return MaterialApp(
      theme: FidaTheme.light,
      home: PhoneAuthGate(
        appName: role == AuthRole.driver ? 'Fida Taxi Driver' : 'Fida Taxi',
        expectedRole: role,
        initialBaseUrl: 'https://api.example.test/api/v1',
        authenticatedBuilder: (context, session, api, signOut) {
          return const SizedBox.shrink();
        },
      ),
    );
  }

  testWidgets('renders rider sign-in with registration option', (tester) async {
    await tester.pumpWidget(buildGate(AuthRole.rider));

    expect(find.text('Sign in to ride'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('New to Fida Taxi? Create an account'), findsOneWidget);
    expect(find.text('Server settings'), findsOneWidget);
    expect(find.text('API server'), findsNothing);
  });

  testWidgets('renders rider registration fields', (tester) async {
    await tester.pumpWidget(buildGate(AuthRole.rider));

    await tester.tap(find.text('New to Fida Taxi? Create an account'));
    await tester.pump();

    expect(find.text('Create account'), findsNWidgets(2));
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
    expect(find.text('Email (optional)'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
  });

  testWidgets('renders driver registration fields', (tester) async {
    await tester.pumpWidget(buildGate(AuthRole.driver));

    expect(find.text('Driver sign in'), findsOneWidget);
    await tester.tap(find.text('New driver? Create an account'));
    await tester.pump();

    expect(find.text('Create driver account'), findsNWidgets(2));
    expect(find.text('Vehicle type'), findsOneWidget);
    expect(find.text('License plate'), findsOneWidget);
  });

  testWidgets('reveals advanced server setting on demand', (tester) async {
    await tester.pumpWidget(buildGate(AuthRole.rider));

    await tester.tap(find.text('Server settings'));
    await tester.pump();

    expect(find.text('API server'), findsOneWidget);
    expect(find.text('Hide server settings'), findsOneWidget);
  });
}
