import 'dart:async';

import 'package:fida_api/fida_api.dart';
import 'package:fida_core/fida_core.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';

class RiderBookingScreen extends StatefulWidget {
  const RiderBookingScreen({
    required this.session,
    required this.api,
    required this.onSignOut,
    super.key,
  });

  final AuthSession session;
  final FidaCoreApi api;
  final VoidCallback onSignOut;

  @override
  State<RiderBookingScreen> createState() => _RiderBookingScreenState();
}

class _RiderBookingScreenState extends State<RiderBookingScreen> {
  final _pickupLatController = TextEditingController();
  final _pickupLngController = TextEditingController();
  final _dropoffLatController = TextEditingController();
  final _dropoffLngController = TextEditingController();

  VehicleType _vehicleType = VehicleType.taxi;
  RidePaymentMethod _paymentMethod = RidePaymentMethod.cash;
  RideSnapshot? _trip;
  RideRequestResult? _requestResult;
  String? _activeTripId;
  String? _errorMessage;
  bool _busy = false;
  bool _refreshing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_recoverActiveTrip());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pickupLatController.dispose();
    _pickupLngController.dispose();
    _dropoffLatController.dispose();
    _dropoffLngController.dispose();
    super.dispose();
  }

  Future<void> _recoverActiveTrip() async {
    try {
      final trip = await widget.api.getActiveRiderTrip(widget.session);
      if (!mounted || trip == null) return;
      setState(() {
        _trip = trip;
        _activeTripId = trip.tripId;
      });
      _startPolling();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    }
  }

  Future<void> _requestRide() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final pickup = GeoPoint(
        latitude: _parseCoordinate(_pickupLatController.text, 'pickup latitude'),
        longitude: _parseCoordinate(
          _pickupLngController.text,
          'pickup longitude',
        ),
      );
      final dropoff = GeoPoint(
        latitude: _parseCoordinate(
          _dropoffLatController.text,
          'destination latitude',
        ),
        longitude: _parseCoordinate(
          _dropoffLngController.text,
          'destination longitude',
        ),
      );

      final result = await widget.api.requestRide(
        session: widget.session,
        request: RideRequest(
          pickup: pickup,
          dropoff: dropoff,
          vehicleType: _vehicleType,
          paymentMethod: _paymentMethod,
        ),
      );
      final trip = await widget.api.getTrip(
        session: widget.session,
        tripId: result.tripId,
      );

      if (!mounted) return;
      setState(() {
        _requestResult = result;
        _trip = trip;
        _activeTripId = trip.tripId;
      });
      _startPolling();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _refreshTrip({bool silent = false}) async {
    final tripId = _activeTripId;
    if (tripId == null || _refreshing) return;

    _refreshing = true;
    try {
      final trip = await widget.api.getTrip(
        session: widget.session,
        tripId: tripId,
      );
      if (!mounted) return;
      setState(() {
        _trip = trip;
        if (!silent) _errorMessage = null;
      });
      if (trip.isTerminal) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } on Object catch (error) {
      if (!mounted || silent) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _cancelRide() async {
    final trip = _trip;
    if (trip == null || !trip.canCancel) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final cancelled = await widget.api.cancelTrip(
        session: widget.session,
        tripId: trip.tripId,
        reason: 'Cancelled from Rider app',
      );
      if (!mounted) return;
      setState(() {
        _trip = cancelled;
      });
      _pollTimer?.cancel();
      _pollTimer = null;
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshTrip(silent: true)),
    );
  }

  void _bookAnotherRide() {
    _pollTimer?.cancel();
    setState(() {
      _trip = null;
      _activeTripId = null;
      _requestResult = null;
      _errorMessage = null;
    });
  }

  double _parseCoordinate(String raw, String label) {
    final value = double.tryParse(raw.trim());
    if (value == null) {
      throw FormatException('Enter a valid $label.');
    }
    return value;
  }

  String _friendlyError(Object error) {
    if (error is FidaApiException) return error.message;
    if (error is ArgumentError || error is FormatException) {
      return error.toString();
    }
    return 'Unable to complete the request. Check the API connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fida Taxi'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refreshTrip(),
          child: ListView(
            padding: const EdgeInsets.all(FidaSpacing.lg),
            children: <Widget>[
              if (trip == null)
                _buildBookingForm(context)
              else
                _buildTrip(context, trip),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: FidaSpacing.lg),
                _ErrorPanel(message: _errorMessage!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Where to?', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: FidaSpacing.xs),
        Text(
          'Enter pickup and destination coordinates for this integration build.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: FidaSpacing.xl),
        _LocationFields(
          title: 'Pickup',
          latitudeController: _pickupLatController,
          longitudeController: _pickupLngController,
        ),
        const SizedBox(height: FidaSpacing.md),
        _LocationFields(
          title: 'Destination',
          latitudeController: _dropoffLatController,
          longitudeController: _dropoffLngController,
        ),
        const SizedBox(height: FidaSpacing.lg),
        DropdownButtonFormField<VehicleType>(
          initialValue: _vehicleType,
          decoration: const InputDecoration(labelText: 'Vehicle'),
          items: VehicleType.values
              .map(
                (type) => DropdownMenuItem<VehicleType>(
                  value: type,
                  child: Text(_vehicleLabel(type)),
                ),
              )
              .toList(growable: false),
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null) setState(() => _vehicleType = value);
                },
        ),
        const SizedBox(height: FidaSpacing.md),
        DropdownButtonFormField<RidePaymentMethod>(
          initialValue: _paymentMethod,
          decoration: const InputDecoration(labelText: 'Payment'),
          items: RidePaymentMethod.values
              .map(
                (method) => DropdownMenuItem<RidePaymentMethod>(
                  value: method,
                  child: Text(_paymentLabel(method)),
                ),
              )
              .toList(growable: false),
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null) setState(() => _paymentMethod = value);
                },
        ),
        const SizedBox(height: FidaSpacing.xl),
        FidaPrimaryButton(
          label: 'Request ride',
          isLoading: _busy,
          onPressed: _requestRide,
        ),
      ],
    );
  }

  Widget _buildTrip(BuildContext context, RideSnapshot trip) {
    final request = _requestResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _statusLabel(trip),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: FidaSpacing.xs),
        Text(
          trip.driverId == null
              ? 'We are matching you with an available driver.'
              : 'Driver assigned: ${trip.driverId}',
        ),
        const SizedBox(height: FidaSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(FidaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DetailRow(label: 'Fare', value: _fareLabel(trip)),
                _DetailRow(
                  label: 'Vehicle',
                  value: _vehicleLabel(trip.vehicleType),
                ),
                _DetailRow(
                  label: 'Payment',
                  value: _paymentLabel(trip.paymentMethod),
                ),
                _DetailRow(
                  label: 'Pickup',
                  value:
                      '${trip.pickup.latitude.toStringAsFixed(5)}, '
                      '${trip.pickup.longitude.toStringAsFixed(5)}',
                ),
                _DetailRow(
                  label: 'Destination',
                  value:
                      '${trip.dropoff.latitude.toStringAsFixed(5)}, '
                      '${trip.dropoff.longitude.toStringAsFixed(5)}',
                ),
                _DetailRow(label: 'Revision', value: '${trip.revision}'),
                if (request != null)
                  _DetailRow(
                    label: 'Drivers found',
                    value: '${request.dispatchCandidateCount}',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FidaSpacing.lg),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _refreshTrip(),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh ride'),
        ),
        if (trip.canCancel) ...<Widget>[
          const SizedBox(height: FidaSpacing.sm),
          TextButton(
            onPressed: _busy ? null : _cancelRide,
            child: const Text('Cancel ride'),
          ),
        ],
        if (trip.isTerminal) ...<Widget>[
          const SizedBox(height: FidaSpacing.sm),
          FidaPrimaryButton(
            label: 'Book another ride',
            onPressed: _bookAnotherRide,
          ),
        ],
      ],
    );
  }

  String _statusLabel(RideSnapshot trip) {
    return switch (trip.domainStatus) {
      RideStatus.quoting => 'Preparing your ride',
      RideStatus.searching => 'Finding a driver',
      RideStatus.driverOffered => 'Driver offer received',
      RideStatus.driverAssigned => 'Driver assigned',
      RideStatus.driverEnRoute => 'Driver is on the way',
      RideStatus.driverArrived => 'Driver has arrived',
      RideStatus.inProgress => 'Trip in progress',
      RideStatus.completed => 'Trip completed',
      RideStatus.paymentPending => 'Payment pending',
      RideStatus.paid => 'Paid',
      RideStatus.cancelledByRider => 'Ride cancelled',
      RideStatus.cancelledByDriver => 'Driver cancelled',
      RideStatus.noDriverFound => 'No driver found',
      RideStatus.paymentFailed => 'Payment failed',
      RideStatus.draft => 'New ride',
      null => trip.status.wireValue.replaceAll('_', ' '),
    };
  }

  String _fareLabel(RideSnapshot trip) {
    final amount = double.tryParse(trip.fareAmount ?? '');
    if (amount == null) return 'Pending';
    final decimals = trip.currency == 'RWF' ? 0 : 2;
    return '${amount.toStringAsFixed(decimals)} ${trip.currency}';
  }

  String _vehicleLabel(VehicleType type) {
    return switch (type) {
      VehicleType.taxi => 'Taxi',
      VehicleType.moto => 'Moto',
      VehicleType.premium => 'Premium',
      VehicleType.tukTuk => 'Tuk Tuk',
      VehicleType.ev => 'Electric',
      VehicleType.accessible => 'Accessible',
      VehicleType.other => 'Other',
    };
  }

  String _paymentLabel(RidePaymentMethod method) {
    return switch (method) {
      RidePaymentMethod.cash => 'Cash',
      RidePaymentMethod.card => 'Card',
      RidePaymentMethod.wallet => 'Wallet',
    };
  }
}

class _LocationFields extends StatelessWidget {
  const _LocationFields({
    required this.title,
    required this.latitudeController,
    required this.longitudeController,
  });

  final String title;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FidaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: FidaSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: latitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: FidaSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: longitudeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FidaSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 104, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FidaSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(FidaRadius.md),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
