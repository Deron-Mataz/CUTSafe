import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// FIX: Robust permission flow + last-known fast-path + stream error handling.
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// Request permission and return whether it was granted.
  Future<bool> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) return false;
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  /// Returns the current GPS position.
  /// Tries last-known first (instant), then accurate fix.
  Future<Position?> getCurrentPosition() async {
    final granted = await requestPermission();
    if (!granted) return null;

    // Fast path — last known position
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (_) {}

    // Accurate fix
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Continuous stream of position updates.
  Stream<Position> positionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy:       LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

  /// Reverse-geocode lat/lng to a human-readable address.
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final p = marks.first;
      return [p.street, p.subLocality, p.locality]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
    } catch (_) {
      return null;
    }
  }

  double distanceMetres(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
}
