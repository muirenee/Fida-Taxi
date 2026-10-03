import 'package:fida_api/fida_api.dart';
import 'package:fida_app_auth/fida_app_auth.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ride/presentation/driver_operations_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FidaTaxiApp()));
}

class FidaTaxiApp extends StatelessWidget {
  const FidaTaxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fida Taxi Driver',
      debugShowCheckedModeBanner: false,
      theme: FidaTheme.light,
      darkTheme: FidaTheme.dark,
      themeMode: ThemeMode.system,
      home: PhoneAuthGate(
        appName: 'Fida Taxi Driver',
        expectedRole: AuthRole.driver,
        authenticatedBuilder: (context, session, api, signOut) {
          return DriverOperationsScreen(
            session: session,
            api: api,
            onSignOut: signOut,
          );
        },
      ),
    );
  }
}
