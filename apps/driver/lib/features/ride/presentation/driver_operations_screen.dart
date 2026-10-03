import 'dart:async';

import 'package:fida_api/fida_api.dart';
import 'package:fida_core/fida_core.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:flutter/material.dart';

class DriverOperationsScreen extends StatefulWidget {
  const DriverOperationsScreen({
    required this.session,
    required this.api,
    required this.onSignOut,
    super.key,
  });

  final AuthSession session;
  final FidaCoreApi api;
  final VoidCallback onSignOut;

  @override
  State<DriverOperationsScreen> createState() => _DriverOperationsScreenState();
}

class _DriverOperationsScreenState extends State<DriverOperationsScreen> {
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  RideSnapshot? _activeTrip;
  List<RideSnapshot> _offers = const <RideSnapshot>[];
  String? _errorMessage;
  bool _available = false;
  bool _busy = false;
  bool _polling = false;
  Timer? _heartbeatTimer;
  Timer? _offerTimer;
  Timer? _tripTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_recoverActiveTrip());
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _offerTimer?.cancel();
    _tripTimer?.cancel();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _recoverActiveTrip() async {
    try {
      final trip = await widget.api.getActiveDriverTrip(widget.session);
      if (!mounted || trip == null) return;
      setState(() {
        _activeTrip = trip;
      });
      _startTripPolling();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    }
  }

  Future<void> _goOnline() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final latitude = _parseCoordinate(_latitudeController.text, 'latitude');
      final longitude = _parseCoordinate(
        _longitudeController.text,
        'longitude',
      );
      await widget.api.setDriverAvailability(
        session: widget.session,
        isAvailable: true,
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      setState(() {
        _available = true;
      });
      _startAvailabilityLoop();
      await _loadOffers();
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

  Future<void> _goOffline() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.api.setDriverAvailability(
        session: widget.session,
        isAvailable: false,
      );
      _stopAvailabilityLoop();
      if (!mounted) return;
      setState(() {
        _available = false;
        _offers = const <RideSnapshot>[];
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startAvailabilityLoop() {
    _heartbeatTimer?.cancel();
    _offerTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_sendHeartbeat()),
    );
    _offerTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_loadOffers(silent: true)),
    );
  }

  void _stopAvailabilityLoop() {
    _heartbeatTimer?.cancel();
    _offerTimer?.cancel();
    _heartbeatTimer = null;
    _offerTimer = null;
  }

  Future<void> _sendHeartbeat() async {
    if (!_available || _activeTrip != null) return;
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) return;

    try {
      await widget.api.setDriverAvailability(
        session: widget.session,
        isAvailable: true,
        latitude: latitude,
        longitude: longitude,
      );
    } on Object {
      // The foreground offer refresh will surface actionable connection errors.
    }
  }

  Future<void> _loadOffers({bool silent = false}) async {
    if (!_available || _activeTrip != null || _polling) return;
    _polling = true;
    try {
      final batch = await widget.api.getDriverOffers(widget.session);
      if (!mounted) return;
      setState(() {
        _offers = batch.offers;
        if (!silent) _errorMessage = null;
      });
    } on Object catch (error) {
      if (!mounted || silent) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      _polling = false;
    }
  }

  Future<void> _acceptRide(RideSnapshot offer) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final trip = await widget.api.acceptTrip(
        session: widget.session,
        tripId: offer.tripId,
      );
      _stopAvailabilityLoop();
      if (!mounted) return;
      setState(() {
        _available = false;
        _offers = const <RideSnapshot>[];
        _activeTrip = trip;
      });
      _startTripPolling();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
      await _loadOffers(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAction(DriverTripAction action) async {
    final trip = _activeTrip;
    if (trip == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final updated = await widget.api.applyDriverAction(
        session: widget.session,
        tripId: trip.tripId,
        action: action,
      );
      if (!mounted) return;
      setState(() {
        _activeTrip = updated;
      });
      if (updated.isTerminal) _stopTripPolling();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTrip() async {
    final trip = _activeTrip;
    if (trip == null || !trip.canCancel) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final cancelled = await widget.api.cancelTrip(
        session: widget.session,
        tripId: trip.tripId,
        reason: 'Cancelled from Driver app',
      );
      _stopTripPolling();
      if (!mounted) return;
      setState(() {
        _activeTrip = cancelled;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startTripPolling() {
    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refreshActiveTrip()),
    );
  }

  void _stopTripPolling() {
    _tripTimer?.cancel();
    _tripTimer = null;
  }

  Future<void> _refreshActiveTrip() async {
    final trip = _activeTrip;
    if (trip == null) return;
    try {
      final updated = await widget.api.getTrip(
        session: widget.session,
        tripId: trip.tripId,
      );
      if (!mounted) return;
      setState(() {
        _activeTrip = updated;
      });
      if (updated.isTerminal) _stopTripPolling();
    } on Object {
      // Manual actions surface failures; background refresh remains quiet.
    }
  }

  void _finishTripCard() {
    setState(() {
      _activeTrip = null;
      _errorMessage = null;
    });
  }

  double _parseCoordinate(String raw, String label) {
    final value = double.tryParse(raw.trim());
    if (value == null) throw FormatException('Enter a valid $label.');
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
    final trip = _activeTrip;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fida Taxi Driver'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FidaSpacing.lg),
          children: <Widget>[
            if (trip != null)
              _buildActiveTrip(context, trip)
            else
              _buildAvailability(context),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: FidaSpacing.lg),
              _ErrorPanel(message: _errorMessage!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvailability(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _available ? 'You are online' : 'You are offline',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Icon(
              Icons.circle,
              size: 14,
              color: _available ? FidaColors.success : FidaColors.muted,
            ),
          ],
        ),
        const SizedBox(height: FidaSpacing.xs),
        Text(
          _available
              ? 'Waiting for nearby ride requests.'
              : 'Set your current dispatch coordinates, then go online.',
        ),
        const SizedBox(height: FidaSpacing.xl),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _latitudeController,
                enabled: !_available && !_busy,
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
                controller: _longitudeController,
                enabled: !_available && !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ),
          ],
        ),
        const SizedBox(height: FidaSpacing.lg),
        FidaPrimaryButton(
          label: _available ? 'Go offline' : 'Go online',
          isLoading: _busy,
          onPressed: _available ? _goOffline : _goOnline,
        ),
        const SizedBox(height: FidaSpacing.xl),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Ride offers',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Refresh offers',
              onPressed: _available && !_busy ? () => _loadOffers() : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: FidaSpacing.sm),
        if (!_available)
          const Text('Go online to receive dispatch offers.')
        else if (_offers.isEmpty)
          const Text('No matching offers right now.')
        else
          ..._offers.map(
            (offer) => _OfferCard(
              offer: offer,
              busy: _busy,
              onAccept: () => _acceptRide(offer),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveTrip(BuildContext context, RideSnapshot trip) {
    final action = _nextAction(trip);
    final actionLabel = _nextActionLabel(trip);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _statusLabel(trip),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: FidaSpacing.xs),
        Text('Trip ${trip.tripId}'),
        const SizedBox(height: FidaSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(FidaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DetailRow(label: 'Rider', value: trip.riderId),
                _DetailRow(label: 'Fare', value: _fareLabel(trip)),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: FidaSpacing.lg),
        if (action != null && actionLabel != null)
          FidaPrimaryButton(
            label: actionLabel,
            isLoading: _busy,
            onPressed: () => _applyAction(action),
          ),
        if (trip.canCancel) ...<Widget>[
          const SizedBox(height: FidaSpacing.sm),
          TextButton(
            onPressed: _busy ? null : _cancelTrip,
            child: const Text('Cancel trip'),
          ),
        ],
        if (trip.isTerminal) ...<Widget>[
          const SizedBox(height: FidaSpacing.sm),
          FidaPrimaryButton(
            label: 'Return to driver home',
            onPressed: _finishTripCard,
          ),
        ],
      ],
    );
  }

  DriverTripAction? _nextAction(RideSnapshot trip) {
    return switch (trip.status) {
      BackendTripStatus.accepted => DriverTripAction.enRoute,
      BackendTripStatus.enRoute => DriverTripAction.arrive,
      BackendTripStatus.arrived => DriverTripAction.start,
      BackendTripStatus.pickedUp => DriverTripAction.complete,
      _ => null,
    };
  }

  String? _nextActionLabel(RideSnapshot trip) {
    return switch (trip.status) {
      BackendTripStatus.accepted => 'Drive to pickup',
      BackendTripStatus.enRoute => 'I have arrived',
      BackendTripStatus.arrived => 'Start trip',
      BackendTripStatus.pickedUp => 'Complete trip',
      _ => null,
    };
  }

  String _statusLabel(RideSnapshot trip) {
    return switch (trip.domainStatus) {
      RideStatus.driverAssigned => 'Ride accepted',
      RideStatus.driverEnRoute => 'Driving to pickup',
      RideStatus.driverArrived => 'Waiting for rider',
      RideStatus.inProgress => 'Trip in progress',
      RideStatus.completed => 'Trip completed',
      RideStatus.cancelledByRider => 'Rider cancelled',
      RideStatus.cancelledByDriver => 'Trip cancelled',
      _ => trip.status.wireValue.replaceAll('_', ' '),
    };
  }

  String _fareLabel(RideSnapshot trip) {
    final amount = double.tryParse(trip.fareAmount ?? '');
    if (amount == null) return 'Pending';
    final decimals = trip.currency == 'RWF' ? 0 : 2;
    return '${amount.toStringAsFixed(decimals)} ${trip.currency}';
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.busy,
    required this.onAccept,
  });

  final RideSnapshot offer;
  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(offer.fareAmount ?? '');
    final fare = amount == null
        ? 'Fare pending'
        : '${amount.toStringAsFixed(offer.currency == 'RWF' ? 0 : 2)} '
              '${offer.currency}';

    return Card(
      margin: const EdgeInsets.only(bottom: FidaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(FidaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(fare, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: FidaSpacing.sm),
            Text(
              'Pickup: ${offer.pickup.latitude.toStringAsFixed(5)}, '
              '${offer.pickup.longitude.toStringAsFixed(5)}',
            ),
            const SizedBox(height: FidaSpacing.xs),
            Text(
              'Destination: ${offer.dropoff.latitude.toStringAsFixed(5)}, '
              '${offer.dropoff.longitude.toStringAsFixed(5)}',
            ),
            const SizedBox(height: FidaSpacing.md),
            FidaPrimaryButton(
              label: 'Accept ride',
              onPressed: busy ? null : onAccept,
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
          SizedBox(width: 96, child: Text(label)),
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
