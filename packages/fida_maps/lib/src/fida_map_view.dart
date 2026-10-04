import 'package:fida_core/fida_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

final class FidaMapView extends StatelessWidget {
  const FidaMapView({
    required this.center,
    this.pickup,
    this.dropoff,
    this.currentLocation,
    this.driverLocation,
    this.route = const <GeoPoint>[],
    this.onTap,
    this.height = 320,
    this.borderRadius = 24,
    super.key,
  });

  final GeoPoint center;
  final GeoPoint? pickup;
  final GeoPoint? dropoff;
  final GeoPoint? currentLocation;
  final GeoPoint? driverLocation;
  final List<GeoPoint> route;
  final ValueChanged<GeoPoint>? onTap;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cameraPoints = <LatLng>[
      if (route.isNotEmpty) ...route.map(_latLng),
      if (pickup != null) _latLng(pickup!),
      if (dropoff != null) _latLng(dropoff!),
      if (currentLocation != null) _latLng(currentLocation!),
      if (driverLocation != null) _latLng(driverLocation!),
    ];

    final cameraFit = cameraPoints.length > 1
        ? CameraFit.coordinates(
            coordinates: cameraPoints,
            padding: const EdgeInsets.all(48),
            maxZoom: 16,
          )
        : null;

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: <Widget>[
            FlutterMap(
              options: MapOptions(
                initialCenter: _latLng(center),
                initialZoom: 15,
                initialCameraFit: cameraFit,
                onTap: onTap == null
                    ? null
                    : (_, point) => onTap!(
                        GeoPoint(
                          latitude: point.latitude,
                          longitude: point.longitude,
                        ),
                      ),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fidalix.fida_taxi',
                  maxNativeZoom: 19,
                ),
                if (route.length >= 2)
                  PolylineLayer(
                    polylines: <Polyline<Object>>[
                      Polyline<Object>(
                        points: route.map(_latLng).toList(growable: false),
                        strokeWidth: 5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _markers(context)),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _markers(BuildContext context) {
    return <Marker>[
      if (pickup != null)
        _marker(
          point: pickup!,
          icon: Icons.trip_origin,
          color: Colors.green.shade700,
          semanticLabel: 'Pickup',
        ),
      if (dropoff != null)
        _marker(
          point: dropoff!,
          icon: Icons.location_on,
          color: Theme.of(context).colorScheme.error,
          semanticLabel: 'Destination',
        ),
      if (currentLocation != null)
        _marker(
          point: currentLocation!,
          icon: Icons.my_location,
          color: Colors.blue.shade700,
          semanticLabel: 'Your location',
        ),
      if (driverLocation != null)
        _marker(
          point: driverLocation!,
          icon: Icons.local_taxi,
          color: Colors.amber.shade800,
          semanticLabel: 'Driver',
        ),
    ];
  }

  Marker _marker({
    required GeoPoint point,
    required IconData icon,
    required Color color,
    required String semanticLabel,
  }) {
    return Marker(
      point: _latLng(point),
      width: 44,
      height: 44,
      child: Semantics(
        label: semanticLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: const <BoxShadow>[
              BoxShadow(blurRadius: 8, color: Color(0x33000000)),
            ],
          ),
          child: Icon(icon, color: color, size: 28),
        ),
      ),
    );
  }

  static LatLng _latLng(GeoPoint point) =>
      LatLng(point.latitude, point.longitude);
}
