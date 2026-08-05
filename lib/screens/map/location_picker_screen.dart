import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';

/// Result returned when the user confirms a location pick.
class PickedLocation {
  final double lat;
  final double lng;
  final String address;
  const PickedLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

/// Full-screen map where the user can:
///  • Drag a pin to any position, OR
///  • Tap "Use My Location" to snap to GPS
/// Returns a [PickedLocation] on confirm, or null on cancel.
class LocationPickerScreen extends StatefulWidget {
  /// Optional initial position (e.g. when editing an existing post).
  final LatLng? initialPosition;

  const LocationPickerScreen({super.key, this.initialPosition});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // CUT Bloemfontein campus as default centre
  static const _defaultCenter = LatLng(-29.1139, 26.1742);

  GoogleMapController? _ctrl;
  LatLng _pinPosition = _defaultCenter;
  String _address = 'Drag the pin or tap "Use My Location"';
  bool _loadingGps = false;
  bool _loadingAddr = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _pinPosition = widget.initialPosition!;
      _resolveAddress(_pinPosition);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  Future<void> _resolveAddress(LatLng pos) async {
    setState(() {
      _loadingAddr = true;
      _address = 'Finding address…';
    });
    final addr = await LocationService.instance
        .reverseGeocode(pos.latitude, pos.longitude);
    if (mounted) {
      setState(() {
        _address = addr ??
            '${pos.latitude.toStringAsFixed(5)}, '
                '${pos.longitude.toStringAsFixed(5)}';
        _loadingAddr = false;
      });
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not get location. Enable GPS and try again.'),
            backgroundColor: AppTheme.cutRed,
          ));
        }
        return;
      }
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinPosition = ll);
      _ctrl?.animateCamera(CameraUpdate.newLatLngZoom(ll, 17));
      await _resolveAddress(ll);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _onCameraIdle() {
    // Called after the user finishes dragging — resolve the address
    // for the current pin position.
    _resolveAddress(_pinPosition);
  }

  void _confirm() {
    Navigator.of(context).pop(PickedLocation(
      lat: _pinPosition.latitude,
      lng: _pinPosition.longitude,
      address: _address,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        actions: [
          TextButton(
            onPressed: _loadingAddr ? null : _confirm,
            child: const Text('Confirm',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(children: [
        // ── Google Map ──────────────────────────────────────────
        GoogleMap(
          onMapCreated: (c) {
            _ctrl = c;
            // Fly to initial position if provided
            if (widget.initialPosition != null) {
              c.animateCamera(
                  CameraUpdate.newLatLngZoom(widget.initialPosition!, 16));
            }
          },
          initialCameraPosition: CameraPosition(
            target: widget.initialPosition ?? _defaultCenter,
            zoom: 15,
          ),
          // Update pin position as the camera moves
          onCameraMove: (pos) => setState(() => _pinPosition = pos.target),
          onCameraIdle: _onCameraIdle,
          myLocationEnabled: true,
          myLocationButtonEnabled: false, // we have our own button
          zoomControlsEnabled: true,
          mapType: MapType.normal,
          // No markers — the centre crosshair IS the pin
        ),

        // ── Centre crosshair pin ────────────────────────────────
        // Stays fixed in the middle while the map moves underneath
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_pin, size: 48, color: AppTheme.cutRed),
              // Offset the icon so the tip sits exactly on the point
              SizedBox(height: 48),
            ],
          ),
        ),

        // ── Address + GPS button bar ────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.cutBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Address display
              Row(children: [
                const Icon(Icons.location_on,
                    color: AppTheme.cutBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: _loadingAddr
                      ? const LinearProgressIndicator()
                      : Text(_address,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 14),

              // Buttons
              Row(children: [
                // Use my location
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingGps ? null : _useMyLocation,
                    icon: _loadingGps
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    label: const Text('My Location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.cutBlue,
                      side: const BorderSide(color: AppTheme.cutBlue),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Confirm
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loadingAddr ? null : _confirm,
                    icon: const Icon(Icons.check),
                    label: const Text('Use This Location'),
                  ),
                ),
              ]),
            ]),
          ),
        ),

        // ── Instruction chip ────────────────────────────────────
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '📍 Drag the map to move the pin',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
