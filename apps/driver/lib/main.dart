import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/ride/presentation/controllers/ride_lifecycle_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: FidaTaxiApp(),
    ),
  );
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
      home: const RideFoundationScreen(),
    );
  }
}

class RideFoundationScreen extends ConsumerWidget {
  const RideFoundationScreen({super.key});

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) {
    final lifecycle = ref.watch(driverRideLifecycleControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fida Taxi Driver'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FidaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Ride lifecycle',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: FidaSpacing.md),
              Text(
                'Status: ' + lifecycle.status.wireValue,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FidaSpacing.xs),
              Text(
                lifecycle.hasServerRide
                    ? 'Ride: ' + lifecycle.rideId!
                    : 'No active server ride.',
              ),
              const SizedBox(height: FidaSpacing.xs),
              Text(
                'Revision: ' + lifecycle.revision.toString(),
              ),
              if (lifecycle.isSynchronizing) ...<Widget>[
                const SizedBox(height: FidaSpacing.lg),
                const LinearProgressIndicator(),
              ],
              if (lifecycle.failureMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: FidaSpacing.lg),
                  child: Text(
                    lifecycle.failureMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
