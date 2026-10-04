import 'dart:async';

import 'package:fida_api/fida_api.dart';
import 'package:fida_core/fida_core.dart';
import 'package:fida_design_system/fida_design_system.dart';
import 'package:fida_maps/fida_maps.dart';
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
  static final GeoPoint _kigaliCenter = GeoPoint(
    latitude: -1.9441,
    longitude: 30.0619,
  );

  final DeviceLocationService _locationService = const DeviceLocationService();
  final TextEditingController _destinationController = TextEditingController();

  VehicleType _vehicleType = VehicleType.taxi;
  RidePaymentMethod _paymentMethod = RidePaymentMethod.cash;
  GeoPoint? _currentLocation;
  GeoPoint? _pickup;
  GeoPoint? _dropoff;
  String _pickupLabel = 'Your current location';
  String? _dropoffLabel;
  List<MapPlace> _searchResults = const <MapPlace>[];
  RoutePreview? _route;
  TripDriverLocation? _driverLocation;
  RideSnapshot? _trip;
  RideRequestResult? _requestResult;
  String? _activeTripId;
  String? _errorMessage;
  bool _busy = false;
  bool _refreshing = false;
  bool _locating = false;
  bool _searching = false;
  bool _routing = false;
  Timer? _pollTimer;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _recoverActiveTrip();
    if (_trip == null) {
      await _useCurrentLocation(silent: true);
    }
  }

  Future<void> _recoverActiveTrip() async {
    try {
      final trip = await widget.api.getActiveRiderTrip(widget.session);
      if (!mounted || trip == null) return;
      setState(() {
        _trip = trip;
        _activeTripId = trip.tripId;
        _pickup = trip.pickup;
        _dropoff = trip.dropoff;
      });
      await _loadTripRoute(trip);
      await _refreshDriverLocation(trip);
      _startPolling();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    }
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      if (!silent) _errorMessage = null;
    });

    try {
      final point = await _locationService.current();
      MapPlace? place;
      try {
        place = await widget.api.reverseGeocode(
          session: widget.session,
          point: point,
        );
      } on Object {
        // Coordinates remain usable when reverse geocoding is unavailable.
      }
      if (!mounted) return;
      setState(() {
        _currentLocation = point;
        _pickup = point;
        _pickupLabel = place?.label ?? 'Your current location';
      });
      if (_dropoff != null) await _loadRoute();
    } on Object catch (error) {
      if (!mounted || silent) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onDestinationChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searchResults = const <MapPlace>[];
        _searching = false;
      });
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_searchDestination(query)),
    );
  }

  Future<void> _searchDestination(String query) async {
    setState(() {
      _searching = true;
      _errorMessage = null;
    });
    try {
      final results = await widget.api.searchPlaces(
        session: widget.session,
        query: query,
        near: _pickup ?? _currentLocation,
      );
      if (!mounted || _destinationController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _searchResults = const <MapPlace>[];
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectDestination(MapPlace place) async {
    _searchDebounce?.cancel();
    setState(() {
      _dropoff = place.point;
      _dropoffLabel = place.label;
      _destinationController.text = place.label;
      _searchResults = const <MapPlace>[];
    });
    await _loadRoute();
  }

  Future<void> _selectDestinationOnMap(GeoPoint point) async {
    setState(() {
      _dropoff = point;
      _dropoffLabel = 'Selected destination';
      _destinationController.text = 'Selected destination';
      _searchResults = const <MapPlace>[];
      _errorMessage = null;
    });

    try {
      final place = await widget.api.reverseGeocode(
        session: widget.session,
        point: point,
      );
      if (!mounted || _dropoff != point) return;
      setState(() {
        _dropoffLabel = place.label;
        _destinationController.text = place.label;
      });
    } on Object {
      // A map-selected coordinate remains valid even without a label.
    }
    await _loadRoute();
  }

  Future<void> _loadRoute() async {
    final pickup = _pickup;
    final dropoff = _dropoff;
    if (pickup == null || dropoff == null || _routing) return;

    setState(() {
      _routing = true;
      _errorMessage = null;
    });
    try {
      final route = await widget.api.getRoutePreview(
        session: widget.session,
        pickup: pickup,
        dropoff: dropoff,
      );
      if (!mounted) return;
      setState(() => _route = route);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _route = null;
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _loadTripRoute(RideSnapshot trip) async {
    try {
      final route = await widget.api.getRoutePreview(
        session: widget.session,
        pickup: trip.pickup,
        dropoff: trip.dropoff,
      );
      if (!mounted || _activeTripId != trip.tripId) return;
      setState(() => _route = route);
    } on Object {
      // Trip status remains usable if the optional route provider is unavailable.
    }
  }

  Future<void> _requestRide() async {
    final pickup = _pickup;
    final dropoff = _dropoff;
    if (pickup == null) {
      setState(() {
        _errorMessage = 'Set your pickup location before requesting a ride.';
      });
      return;
    }
    if (dropoff == null) {
      setState(() {
        _errorMessage = 'Search for or select a destination first.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
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
      if (mounted) setState(() => _busy = false);
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
      await _refreshDriverLocation(trip);
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

  Future<void> _refreshDriverLocation(RideSnapshot trip) async {
    if (trip.driverId == null) {
      if (mounted) setState(() => _driverLocation = null);
      return;
    }

    try {
      final location = await widget.api.getTripDriverLocation(
        session: widget.session,
        tripId: trip.tripId,
      );
      if (!mounted || _activeTripId != trip.tripId) return;
      setState(() => _driverLocation = location);
    } on Object {
      // A stale/missing driver position must not hide trip status.
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
      setState(() => _trip = cancelled);
      _pollTimer?.cancel();
      _pollTimer = null;
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
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
      _driverLocation = null;
      _dropoff = null;
      _dropoffLabel = null;
      _route = null;
      _destinationController.clear();
      _errorMessage = null;
    });
    unawaited(_useCurrentLocation(silent: true));
  }

  String _friendlyError(Object error) {
    if (error is FidaApiException) return error.message;
    if (error is LocationAccessException) return error.message;
    if (error is ArgumentError || error is FormatException) {
      return error.toString();
    }
    return 'Unable to complete the request. Check your connection and try again.';
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
          onRefresh: trip == null
              ? () => _useCurrentLocation()
              : () => _refreshTrip(),
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
    final center = _pickup ?? _currentLocation ?? _kigaliCenter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Where to?', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: FidaSpacing.xs),
        Text(
          'Search a destination or tap the map. Your current GPS position is used as pickup.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: FidaSpacing.lg),
        FidaMapView(
          center: center,
          pickup: _pickup,
          dropoff: _dropoff,
          currentLocation: _currentLocation,
          route: _route?.points ?? const <GeoPoint>[],
          onTap: _selectDestinationOnMap,
        ),
        const SizedBox(height: FidaSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(FidaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.my_location, size: 20),
                    ),
                    const SizedBox(width: FidaSpacing.sm),
                    Expanded(
                      child: Text(
                        _pickup == null ? 'Pickup not set' : _pickupLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _locating ? null : () => _useCurrentLocation(),
                      child: Text(_locating ? 'Locating…' : 'Use GPS'),
                    ),
                  ],
                ),
                const Divider(),
                TextField(
                  controller: _destinationController,
                  onChanged: _onDestinationChanged,
                  enabled: !_busy,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Destination',
                    hintText: 'Search a place in Rwanda',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
                if (_searchResults.isNotEmpty) ...<Widget>[
                  const SizedBox(height: FidaSpacing.sm),
                  ..._searchResults.map(
                    (place) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(
                        place.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectDestination(place),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_route != null || _routing) ...<Widget>[
          const SizedBox(height: FidaSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(FidaSpacing.md),
              child: _routing
                  ? const Row(
                      children: <Widget>[
                        SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: FidaSpacing.sm),
                        Text('Building route…'),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        const Icon(Icons.route),
                        const SizedBox(width: FidaSpacing.sm),
                        Expanded(
                          child: Text(
                            '${_route!.distanceKm.toStringAsFixed(1)} km · ${_durationLabel(_route!.duration)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
        const SizedBox(height: FidaSpacing.md),
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
        if (_dropoffLabel != null) ...<Widget>[
          const SizedBox(height: FidaSpacing.sm),
          Text(
            _dropoffLabel!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: FidaSpacing.xl),
        FidaPrimaryButton(
          label: 'Request ride',
          isLoading: _busy,
          onPressed: _pickup != null && _dropoff != null ? _requestRide : null,
        ),
      ],
    );
  }

  Widget _buildTrip(BuildContext context, RideSnapshot trip) {
    final request = _requestResult;
    final driverPoint = _driverLocation?.point;

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
              : driverPoint == null
              ? 'Driver assigned. Waiting for a live location update.'
              : 'Your driver is live on the map.',
        ),
        const SizedBox(height: FidaSpacing.lg),
        FidaMapView(
          center: driverPoint ?? trip.pickup,
          pickup: trip.pickup,
          dropoff: trip.dropoff,
          driverLocation: driverPoint,
          route: _route?.points ?? const <GeoPoint>[],
          height: 340,
        ),
        const SizedBox(height: FidaSpacing.md),
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
                if (_route != null)
                  _DetailRow(
                    label: 'Route',
                    value:
                        '${_route!.distanceKm.toStringAsFixed(1)} km · ${_durationLabel(_route!.duration)}',
                  ),
                _DetailRow(label: 'Revision', value: '${trip.revision}'),
                if (request != null)
                  _DetailRow(
                    label: 'Drivers found',
                    value: '${request.dispatchCandidateCount}',
                  ),
                if (_driverLocation?.observedAt != null)
                  _DetailRow(
                    label: 'Driver GPS',
                    value: _driverLocation!.observedAt!.toLocal().toString(),
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

  String _durationLabel(Duration duration) {
    final minutes = (duration.inSeconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '$hours h' : '$hours h $remaining min';
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
