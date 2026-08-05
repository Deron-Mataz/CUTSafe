import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../models/alert_model.dart';
import '../../models/campus_boundary.dart';
import '../../providers/alert_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

class MapScreen extends StatefulWidget {
  final LatLng? focusTarget;
  final String? focusLabel;
  const MapScreen({super.key, this.focusTarget, this.focusLabel});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  GoogleMapController? _ctrl;

  static const _bfn    = LatLng(-29.12176, 26.21281);
  static const _welkom = LatLng(-27.94916, 26.78367);

  Position? _myPos;
  LatLng?   _smoothPos;
  StreamSubscription<Position>? _posSub;
  bool _autoFollow = true;
  bool _hasInitMap = false;

  bool _serviceOff = false, _permDenied = false, _permForever = false;
  bool _showBoundary = true;

  // FIX (real cause of lag): CampusBoundary.allPolygons() was being called
  // fresh inside build() every single time — and this screen rebuilds on
  // every AlertProvider snapshot (which fires constantly, unrelated to the
  // map itself). Each rebuild recreated all 7 polygons (dozens of vertices
  // each) as brand-new objects, forcing GoogleMap to re-diff and re-upload
  // the entire polygon overlay to the native map view — including mid-
  // gesture while the user was actively panning/zooming. Computed ONCE
  // here and never rebuilt.
  late final Set<Polygon> _boundaryPolygons = CampusBoundary.allPolygons();

  // FIX: while _autoFollow was on, every single position update called
  // _flyTo() -> animateCamera(), even if the user was mid-drag on the map.
  // That meant the camera was constantly being yanked back to "follow"
  // while the user's own pan gesture was still in flight — a direct fight
  // between user input and programmatic animation, which reads as lag/
  // jank even though each individual call is cheap. Two fixes:
  //  1. Throttle _flyTo to at most once every 2 seconds while following
  //     (you explicitly said a few seconds' delay on location refresh is
  //     fine in exchange for smoothness).
  //  2. Detect an actual user-initiated drag (as opposed to our own
  //     programmatic animateCamera call) and auto-disable autoFollow,
  //     exactly like the native Google Maps app does.
  DateTime? _lastFlyTo;
  bool _isProgrammaticMove = false;
  AlertCategory? _filter;

  // ── FIX: "me" is now a real native Marker, not a Flutter overlay ────
  // The previous approach positioned a Flutter widget using
  // GoogleMapController.getScreenCoordinate() on a timer. That call is
  // an async platform-channel round trip computed AFTER the native map
  // has already redrawn for the current frame — so the overlay is
  // structurally always one step behind whatever the map is currently
  // showing. During continuous zoom/pan this shows up exactly as
  // "playing catch-up". A native Marker has no such gap: its LatLng is
  // handed to the native map SDK once, and the SDK itself repositions it
  // in lock-step with every camera frame, identical to any other marker.
  //
  // To still get a "pulsing" look without per-frame Flutter work, two
  // bitmap frames (thin ring / thick ring) are pre-rendered once and the
  // marker's `icon` is swapped between them on a slow timer — cheap,
  // and completely decoupled from camera movement.
  ui.Image?          _avatarPhoto;
  BitmapDescriptor?  _meIconA;
  BitmapDescriptor?  _meIconB;
  bool               _pulseFrame = false;
  Timer?             _pulseTimer;
  bool               _lastSOSColorState = false;

  Future<void> _loadAvatarPhoto(String? url) async {
    if (url == null || url.isEmpty) { _avatarPhoto = null; return; }
    try {
      final completer = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      }, onError: (e, st) {
        completer.completeError(e);
        stream.removeListener(listener);
      });
      stream.addListener(listener);
      _avatarPhoto = await completer.future;
    } catch (_) {
      _avatarPhoto = null;
    }
  }

  Future<BitmapDescriptor> _renderAvatarIcon({
    required String initials,
    required bool sos,
    required double ringWidth,
  }) async {
    // FIX: avatar marker was too large — shrunk to a third of its
    // previous canvas size (132 -> 44), which shrinks the final
    // rendered size on the map proportionally.
    const size = 44.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    final center = const Offset(size / 2, size / 2);
    final photoRadius = size / 2 - ringWidth - 2;
    final ringColor = sos ? AppTheme.cutRed : Colors.green;

    // Soft white halo behind the ring for contrast against any map colour
    canvas.drawCircle(center, photoRadius + ringWidth + 1.3, Paint()..color = Colors.white);

    if (_avatarPhoto != null) {
      final src = Rect.fromLTWH(0, 0, _avatarPhoto!.width.toDouble(), _avatarPhoto!.height.toDouble());
      final dst = Rect.fromCircle(center: center, radius: photoRadius);
      canvas.save();
      canvas.clipPath(Path()..addOval(dst));
      canvas.drawImageRect(_avatarPhoto!, src, dst, Paint());
      canvas.restore();
    } else {
      canvas.drawCircle(center, photoRadius, Paint()..color = AppTheme.cutBlue);
      final tp = TextPainter(
        text: TextSpan(text: initials, style: TextStyle(
            color: Colors.white, fontSize: photoRadius * 0.75, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.drawCircle(center, photoRadius + ringWidth / 2, Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _regenerateAvatarIcons(String initials, bool sos) async {
    _meIconA = await _renderAvatarIcon(initials: initials, sos: sos, ringWidth: 1.7);
    _meIconB = await _renderAvatarIcon(initials: initials, sos: sos, ringWidth: 3);
    _lastSOSColorState = sos;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _initLocation();
    // Slow timer just swaps between two pre-rendered bitmap frames —
    // no per-tick drawing, no platform-channel calls, no dependency on
    // camera state at all. Purely cosmetic and fully decoupled from map
    // interaction, so it can never contribute to gesture lag.
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (mounted) setState(() => _pulseFrame = !_pulseFrame);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ctrl?.dispose();
    _pulseTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _serviceOff = true);
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _permForever = true);
      return;
    }
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) { if (mounted) setState(() => _permDenied = true); return; }
      if (perm == LocationPermission.deniedForever) { if (mounted) setState(() => _permForever = true); return; }
    }
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        final ll = LatLng(last.latitude, last.longitude);
        setState(() { _myPos = last; _smoothPos = ll; });
      }
    } catch (_) {}
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        setState(() { _myPos = pos; _smoothPos = ll; });
        if (!_hasInitMap) { _hasInitMap = true; _flyTo(ll, zoom: 15, force: true); }
        else if (_autoFollow) { _flyTo(ll); }
      }
    } catch (_) {}
    if (widget.focusTarget != null && mounted) _flyTo(widget.focusTarget!, zoom: 17, force: true);

    _posSub = LocationService.instance.positionStream().listen((p) {
      if (!mounted) return;
      final ll = LatLng(p.latitude, p.longitude);
      setState(() { _myPos = p; _smoothPos = ll; });
      if (_autoFollow) _flyTo(ll);
      if (!_hasInitMap) { _hasInitMap = true; _flyTo(ll, zoom: 15, force: true); }
    }, onError: (_) {});
  }

  void _flyTo(LatLng target, {double? zoom, bool force = false}) {
    if (_ctrl == null) return;
    // Throttle: skip re-centering calls that arrive within 2s of the last
    // one, unless this is a forced move (initial fix, focus target, manual
    // campus jump, or the "my location" FAB — those should always fire
    // immediately).
    if (!force) {
      final now = DateTime.now();
      if (_lastFlyTo != null && now.difference(_lastFlyTo!) < const Duration(seconds: 2)) {
        return;
      }
      _lastFlyTo = now;
    }
    _isProgrammaticMove = true;
    if (zoom != null) {
      _ctrl!.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } else {
      _ctrl!.animateCamera(CameraUpdate.newLatLng(target));
    }
  }

  Set<Marker> _buildMarkers(List<AlertModel> alerts) {
    final markers = <Marker>{
      Marker(markerId: const MarkerId('campus_bfn'), position: _bfn,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'CUT Bloemfontein'), zIndex: 5),
      Marker(markerId: const MarkerId('campus_welkom'), position: _welkom,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'CUT Welkom'), zIndex: 5),
    };

    // FIX: "me" is now a real native Marker (icon generated from the
    // user's photo + a coloured ring) instead of a Flutter overlay
    // positioned via async getScreenCoordinate — this is what eliminates
    // the "playing catch-up" lag during pan/zoom, since a Marker's
    // position is handled entirely by the native map SDK in lock-step
    // with every camera frame.
    if (_smoothPos != null && (_meIconA != null || _meIconB != null)) {
      final icon = (_pulseFrame ? _meIconB : _meIconA) ?? _meIconA ?? _meIconB!;
      markers.add(Marker(
        markerId: const MarkerId('_me'),
        position: _smoothPos!,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: '📍 You are here'),
        zIndex: 25,
      ));
    }

    if (widget.focusTarget != null) {
      markers.add(Marker(markerId: const MarkerId('_focus'), position: widget.focusTarget!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: widget.focusLabel ?? 'Incident'), zIndex: 15));
    }

    final filtered = _filter == null ? alerts : alerts.where((a) => a.category == _filter).toList();
    for (final alert in filtered) {
      if (!alert.hasCoords) continue;
      final pos = LatLng(alert.latitude!, alert.longitude!);
      if (alert.isSOS) {
        markers.add(Marker(markerId: MarkerId('sos_${alert.id}'), position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: alert.isSOSSafe ? '✅ SOS (SAFE) — ${alert.userName}' : '🚨 SOS ACTIVE — ${alert.userName}',
            snippet: alert.location ?? '', onTap: () => _showAlertSheet(alert)),
          zIndex: 18));
        continue;
      }
      markers.add(Marker(markerId: MarkerId(alert.id), position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(_hue(alert.category)),
        infoWindow: InfoWindow(title: alert.title, snippet: '${alert.category.label} · Tap for details', onTap: () => _showAlertSheet(alert)),
        zIndex: 10));
    }
    return markers;
  }

  double _hue(AlertCategory c) => switch (c) {
    AlertCategory.crime   => BitmapDescriptor.hueRed,
    AlertCategory.medical => BitmapDescriptor.hueCyan,
    AlertCategory.hazard  => BitmapDescriptor.hueYellow,
    AlertCategory.sos     => BitmapDescriptor.hueRed,
    AlertCategory.other   => BitmapDescriptor.hueViolet,
  };

  Color _catColor(AlertCategory c) => switch (c) {
    AlertCategory.crime   => AppTheme.cutRed,
    AlertCategory.medical => Colors.teal,
    AlertCategory.hazard  => Colors.orange,
    AlertCategory.sos     => AppTheme.cutRed,
    AlertCategory.other   => AppTheme.cutMuted,
  };

  void _showAlertSheet(AlertModel alert) {
    final uid = context.read<UserProvider>().user?.id ?? '';
    showModalBottomSheet(context: context, isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _AlertMapSheet(alert: alert, uid: uid));
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Filter Map Pins', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_filter != null) TextButton(onPressed: () { setState(() => _filter = null); setModal(() {}); Navigator.pop(ctx); }, child: const Text('Clear')),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 10, children: [
              _FilterChip(label: 'All', selected: _filter == null, color: AppTheme.cutBlue,
                  onTap: () { setState(() => _filter = null); setModal(() {}); Navigator.pop(ctx); }),
              ...[AlertCategory.crime, AlertCategory.medical, AlertCategory.hazard, AlertCategory.sos, AlertCategory.other]
                  .map((c) => _FilterChip(label: c.label, selected: _filter == c, color: _catColor(c),
                      onTap: () { setState(() => _filter = c); setModal(() {}); Navigator.pop(ctx); })),
            ]),
          ]),
        ),
      )),
    );
  }

  void _showAreaSheet(String label) {
    showModalBottomSheet(context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Row(children: [const Icon(Icons.school_outlined, color: AppTheme.cutBlue, size: 22), const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))]))));
  }

  void _maybeHandleAreaTap(LatLng tap) {
    if (!_showBoundary) return;
    final areas = {
      'Main Campus': CampusBoundary.bfnMainCampus, 'FEBIT': CampusBoundary.bfnFebit,
      'Sports Grounds': CampusBoundary.bfnSportsGrounds, 'Loggies Residence': CampusBoundary.bfnLoggiesResidence,
      'Mennheim Men & Ladies': CampusBoundary.bfnMennheim, 'Gmynos Residence': CampusBoundary.bfnGmynosResidence,
      'Welkom Campus': CampusBoundary.welkomCampus,
    };
    for (final entry in areas.entries) {
      if (_pointInPolygon(tap, entry.value)) { _showAreaSheet(entry.key); return; }
    }
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    final alerts           = context.watch<AlertProvider>().alerts;
    final alertsWithCoords = alerts.where((a) => a.hasCoords).length;
    final activeSOSCount   = alerts.where((a) => a.isSOSActive).length;
    final me   = context.watch<UserProvider>().user;
    // Is the current user's own SOS active? Drives the avatar ring colour.
    final myActiveSOS = me != null && alerts.any((a) => a.userId == me.id && a.isSOSActive);

    // (Re)generate the avatar bitmap icons once, and again whenever the
    // SOS colour state flips (green <-> red) or the photo first loads.
    if (me != null && (_meIconA == null || _lastSOSColorState != myActiveSOS)) {
      _loadAvatarPhoto(me.photoUrl).then((_) => _regenerateAvatarIcons(me.initials, myActiveSOS));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Safety Map'),
          Row(children: [
            Text('$alertsWithCoords pin${alertsWithCoords == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            if (activeSOSCount > 0) ...[
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                  child: Text('$activeSOSCount SOS ACTIVE', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
            ],
          ]),
        ]),
        actions: [
          IconButton(icon: Icon(_showBoundary ? Icons.layers : Icons.layers_outlined, color: _showBoundary ? Colors.yellowAccent : Colors.white),
              tooltip: 'Toggle campus boundary', onPressed: () => setState(() => _showBoundary = !_showBoundary)),
          IconButton(icon: Icon(_autoFollow ? Icons.navigation : Icons.navigation_outlined, color: _autoFollow ? Colors.yellowAccent : Colors.white),
              onPressed: () => setState(() => _autoFollow = !_autoFollow)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.school_outlined, color: Colors.white),
            onSelected: (v) { setState(() => _autoFollow = false); _flyTo(v == 'bfn' ? _bfn : _welkom, zoom: 16, force: true); },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bfn', child: Text('Bloemfontein Campus')),
              PopupMenuItem(value: 'welkom', child: Text('Welkom Campus')),
            ],
          ),
          IconButton(icon: Icon(Icons.filter_list, color: _filter != null ? Colors.yellowAccent : Colors.white), onPressed: _showFilterSheet),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          onMapCreated: (c) {
            _ctrl = c;
            if (widget.focusTarget != null) { _flyTo(widget.focusTarget!, zoom: 17, force: true); }
            else if (_smoothPos != null) { _flyTo(_smoothPos!, zoom: 15, force: true); }
          },
          onTap: (latLng) => _maybeHandleAreaTap(latLng),
          // Auto-disables follow on a genuine user drag (unchanged) —
          // no longer needs to also trigger avatar repositioning since
          // the avatar is now a native marker the map handles itself.
          onCameraMoveStarted: () {
            if (!_isProgrammaticMove && _autoFollow) {
              setState(() => _autoFollow = false);
            }
          },
          onCameraIdle: () {
            _isProgrammaticMove = false;
          },
          initialCameraPosition: CameraPosition(target: widget.focusTarget ?? _bfn, zoom: widget.focusTarget != null ? 17 : 14),
          markers: _buildMarkers(alerts),
          polygons: _showBoundary ? _boundaryPolygons : const {},
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          compassEnabled: true,
        ),

        Positioned(top: 10, left: 10, child: _Legend(filter: _filter, catColor: _catColor, showBoundary: _showBoundary)),

        if (_myPos != null) Positioned(bottom: 80, left: 12, child: _DistanceBadge(myPos: _myPos!)),

        Positioned(bottom: 24, right: 12,
          child: FloatingActionButton.small(heroTag: 'fab_locate',
            onPressed: () { setState(() => _autoFollow = true); if (_smoothPos != null) _flyTo(_smoothPos!, zoom: 17, force: true); },
            backgroundColor: AppTheme.cutBlue, child: const Icon(Icons.my_location, color: Colors.white, size: 20))),

        if (_serviceOff) _Banner(icon: Icons.location_disabled, message: 'Location services are off.', buttonLabel: 'Open Settings', onTap: () => Geolocator.openLocationSettings()),
        if (_permForever && !_serviceOff) _Banner(icon: Icons.location_off, message: 'Location permission denied. Grant it in app settings.', buttonLabel: 'App Settings', onTap: () => Geolocator.openAppSettings()),
        if (_permDenied && !_permForever && !_serviceOff) _Banner(icon: Icons.location_off, message: 'Location access denied.', buttonLabel: 'Allow',
            onTap: () async { setState(() => _permDenied = false); await _initLocation(); }),

        if (_myPos == null && !_serviceOff && !_permDenied && !_permForever)
          Positioned(bottom: 80, left: 0, right: 0, child: Center(
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                SizedBox(width: 10), Text('Getting your location…', style: TextStyle(color: Colors.white, fontSize: 13)),
              ])))),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon; final String message, buttonLabel; final VoidCallback onTap;
  const _Banner({required this.icon, required this.message, required this.buttonLabel, required this.onTap});
  @override
  Widget build(BuildContext context) => Positioned(bottom: 80, left: 12, right: 12,
    child: Material(borderRadius: BorderRadius.circular(12), color: Colors.black87,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(icon, color: Colors.orange, size: 20), const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 12))),
          TextButton(onPressed: onTap, child: Text(buttonLabel, style: const TextStyle(color: Colors.yellowAccent, fontSize: 12))),
        ]))));
}

class _Legend extends StatelessWidget {
  final AlertCategory? filter;
  final Color Function(AlertCategory) catColor;
  final bool showBoundary;
  const _Legend({this.filter, required this.catColor, this.showBoundary = true});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Text('Legend', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
      const SizedBox(height: 6),
      const _LegRow(color: Colors.green, label: 'You (live)'),
      const _LegRow(color: AppTheme.cutBlue, label: 'Campus'),
      if (showBoundary) const _LegRow(color: Color(0x66757575), label: 'Campus boundary'),
      ...[AlertCategory.crime, AlertCategory.medical, AlertCategory.hazard, AlertCategory.sos, AlertCategory.other]
          .map((c) => _LegRow(color: catColor(c), label: c.label, dimmed: filter != null && filter != c)),
    ]));
}

class _LegRow extends StatelessWidget {
  final Color color; final String label; final bool dimmed;
  const _LegRow({required this.color, required this.label, this.dimmed = false});
  @override
  Widget build(BuildContext context) => Opacity(opacity: dimmed ? 0.3 : 1,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 11)),
      ])));
}

class _DistanceBadge extends StatelessWidget {
  final dynamic myPos;
  static const _bfn = LatLng(-29.12176, 26.21281);
  static const _welkom = LatLng(-27.94916, 26.78367);
  const _DistanceBadge({required this.myPos});
  @override
  Widget build(BuildContext context) {
    final toBfn = Geolocator.distanceBetween(myPos.latitude, myPos.longitude, _bfn.latitude, _bfn.longitude);
    final toWlk = Geolocator.distanceBetween(myPos.latitude, myPos.longitude, _welkom.latitude, _welkom.longitude);
    final isBfn = toBfn <= toWlk;
    final dist = isBfn ? toBfn : toWlk;
    final campus = isBfn ? 'BFN Campus' : 'Welkom Campus';
    final distLabel = dist < 1000 ? '${dist.round()} m' : '${(dist / 1000).toStringAsFixed(1)} km';
    final onCampus = dist < 500;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: onCampus ? Colors.green : Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(onCampus ? Icons.check_circle_outline : Icons.school_outlined, color: onCampus ? Colors.white : AppTheme.cutBlue, size: 14),
        const SizedBox(width: 6),
        Text(onCampus ? 'On $campus' : '$distLabel from $campus',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: onCampus ? Colors.white : AppTheme.cutDark)),
      ]));
  }
}

class _AlertMapSheet extends StatelessWidget {
  final AlertModel alert; final String uid;
  const _AlertMapSheet({required this.alert, required this.uid});
  Color _cc() {
    if (alert.isSOS) return AppTheme.cutRed;
    switch (alert.category) {
      case AlertCategory.crime: return AppTheme.cutRed;
      case AlertCategory.medical: return Colors.teal;
      case AlertCategory.hazard: return Colors.orange;
      default: return AppTheme.cutMuted;
    }
  }
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final reported = prov.hasReported(alert.id);
    final isOwner = alert.userId == uid;
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppTheme.cutBorder, borderRadius: BorderRadius.circular(2)))),
        if (alert.isSOS) ...[
          Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: alert.isSOSActive ? AppTheme.cutRed : Colors.green, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(alert.isSOSActive ? Icons.emergency : Icons.check_circle_outline, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(alert.isSOSActive ? '🚨 SOS ACTIVE — Needs help!' : '✅ SOS — Person is now safe',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            ])),
          const SizedBox(height: 12),
        ] else ...[
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _cc().withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: _cc().withOpacity(0.4))),
            child: Text(alert.category.label, style: TextStyle(color: _cc(), fontWeight: FontWeight.w700, fontSize: 12))),
          const SizedBox(height: 12),
        ],
        Text(alert.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(alert.description, style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.cutDark), maxLines: 4, overflow: TextOverflow.ellipsis),
        if (alert.location != null) ...[const SizedBox(height: 10),
          Row(children: [const Icon(Icons.location_on, color: AppTheme.cutBlue, size: 15), const SizedBox(width: 6),
            Expanded(child: Text(alert.location!, style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)))])],
        const SizedBox(height: 16),
        if (isOwner && alert.isSOSActive) SizedBox(width: double.infinity,
          child: ElevatedButton.icon(onPressed: () { prov.markSOSSafe(alert.id); Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Marked as Safe.'))); },
            icon: const Icon(Icons.check_circle_outline, color: Colors.white), label: const Text('Mark Myself as Safe'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green))),
        if (!isOwner) Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: alert.isConfirmed ? null : () { prov.confirmAlert(alert.id, uid); Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for confirming!'))); },
            icon: Icon(Icons.check_circle_outline, size: 16, color: alert.isConfirmed ? Colors.green : AppTheme.cutBlue),
            label: Text(alert.isConfirmed ? 'Confirmed' : 'I Saw This', style: TextStyle(fontSize: 12, color: alert.isConfirmed ? Colors.green : AppTheme.cutBlue)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), side: BorderSide(color: alert.isConfirmed ? Colors.green : AppTheme.cutBlue)))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            onPressed: reported ? null : () { prov.reportAlert(alert.id, uid); Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alert reported.'))); },
            icon: Icon(Icons.flag_outlined, size: 16, color: reported ? AppTheme.cutMuted : AppTheme.cutRed),
            label: Text(reported ? 'Reported' : 'Report', style: TextStyle(fontSize: 12, color: reported ? AppTheme.cutMuted : AppTheme.cutRed)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), side: BorderSide(color: reported ? AppTheme.cutMuted : AppTheme.cutRed)))),
        ]),
      ]),
    ));
  }
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected; final Color color; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(color: selected ? color : color.withOpacity(0.08), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : color.withOpacity(0.4), width: selected ? 2 : 1)),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w600, fontSize: 13))));
}
