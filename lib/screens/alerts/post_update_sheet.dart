import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../../providers/alert_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../map/location_picker_screen.dart';

class PostUpdateSheet extends StatefulWidget {
  const PostUpdateSheet({super.key});
  @override
  State<PostUpdateSheet> createState() => _PostUpdateSheetState();
}

class _PostUpdateSheetState extends State<PostUpdateSheet> {
  final _form = GlobalKey<FormState>();
  final _content = TextEditingController();
  final _loc = TextEditingController();

  double? _lat, _lng;
  bool _fetchingGps = false;
  bool _loadingSuggestions = false;
  bool _showSuggestions = false;
  List<_Sug> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loc.addListener(_onLocChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _content.dispose();
    _loc.removeListener(_onLocChanged);
    _loc.dispose();
    super.dispose();
  }

  void _onLocChanged() {
    if (_lat != null && _lng != null) return;
    final q = _loc.text.trim();
    _debounce?.cancel();
    if (q.length < 3) {
      if (_showSuggestions) {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    if (!mounted) return;
    setState(() => _loadingSuggestions = true);
    try {
      final locs = await locationFromAddress(q);
      final results = <_Sug>[];
      for (final loc in locs.take(5)) {
        final addr = await LocationService.instance
                .reverseGeocode(loc.latitude, loc.longitude) ??
            q;
        results.add(_Sug(label: addr, lat: loc.latitude, lng: loc.longitude));
      }
      if (mounted) {
        setState(() {
          _suggestions = results;
          _showSuggestions = results.isNotEmpty;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  void _pick(_Sug s) {
    _debounce?.cancel();
    _loc.removeListener(_onLocChanged);
    _loc.text = s.label;
    _loc.addListener(_onLocChanged);
    setState(() {
      _lat = s.lat;
      _lng = s.lng;
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  Future<void> _openMapPicker() async {
    final initial =
        (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    final result = await Navigator.of(context).push<PickedLocation>(
        MaterialPageRoute(
            builder: (_) => LocationPickerScreen(initialPosition: initial),
            fullscreenDialog: true));
    if (result != null && mounted) {
      _debounce?.cancel();
      _loc.removeListener(_onLocChanged);
      _loc.text = result.address;
      _loc.addListener(_onLocChanged);
      setState(() {
        _lat = result.lat;
        _lng = result.lng;
        _suggestions = [];
        _showSuggestions = false;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _fetchingGps = true);
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not get location. Enable GPS.'),
              backgroundColor: AppTheme.cutRed));
        }
        return;
      }
      final addr = await LocationService.instance
              .reverseGeocode(pos.latitude, pos.longitude) ??
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      if (mounted) {
        _debounce?.cancel();
        _loc.removeListener(_onLocChanged);
        _loc.text = addr;
        _loc.addListener(_onLocChanged);
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _suggestions = [];
          _showSuggestions = false;
        });
      }
    } finally {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    final err = await context.read<AlertProvider>().postUpdate(
          userId: user.id,
          userName: user.name,
          userPhotoUrl: user.photoUrl,
          content: _content.text.trim(),
          location: _loc.text.trim().isEmpty ? null : _loc.text.trim(),
        );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Update posted.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppTheme.cutRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AlertProvider>().isLoading;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final hasPin = _lat != null && _lng != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: AppTheme.cutBorder,
                              borderRadius: BorderRadius.circular(2)))),
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppTheme.cutBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.campaign_outlined,
                            color: AppTheme.cutBlue, size: 22)),
                    const SizedBox(width: 12),
                    const Text('Post Update',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 20),
                  TextFormField(
                      controller: _content,
                      maxLines: 5,
                      decoration: const InputDecoration(
                          labelText: 'What would you like to share? *',
                          alignLabelWithHint: true),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _loc,
                    decoration: InputDecoration(
                      hintText: 'Type or search for a location…',
                      prefixIcon: Icon(
                        hasPin
                            ? Icons.location_on
                            : Icons.location_off_outlined,
                        color: hasPin ? AppTheme.cutBlue : AppTheme.cutMuted,
                      ),
                      suffixIcon:
                          Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_loadingSuggestions)
                          const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.cutBlue))),
                        if (_loc.text.isNotEmpty)
                          IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppTheme.cutMuted, size: 18),
                              onPressed: () {
                                _debounce?.cancel();
                                _loc.removeListener(_onLocChanged);
                                _loc.clear();
                                _loc.addListener(_onLocChanged);
                                setState(() {
                                  _lat = null;
                                  _lng = null;
                                  _suggestions = [];
                                  _showSuggestions = false;
                                });
                              }),
                      ]),
                      filled: true,
                      fillColor: hasPin
                          ? AppTheme.cutBlue.withValues(alpha: 0.05)
                          : AppTheme.cutGrey,
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: hasPin
                                  ? AppTheme.cutBlue
                                  : AppTheme.cutBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppTheme.cutBlue, width: 2)),
                    ),
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.cutBorder),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 4))
                          ]),
                      child: Column(
                        children: _suggestions.asMap().entries.map((e) {
                          final isLast = e.key == _suggestions.length - 1;
                          return InkWell(
                            onTap: () => _pick(e.value),
                            borderRadius: isLast
                                ? const BorderRadius.only(
                                    bottomLeft: Radius.circular(10),
                                    bottomRight: Radius.circular(10))
                                : BorderRadius.zero,
                            child: Column(children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 16, color: AppTheme.cutBlue),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(e.value.label,
                                          style:
                                              const TextStyle(fontSize: 13))),
                                ]),
                              ),
                              if (!isLast) const Divider(height: 1, indent: 40),
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                      onPressed: _openMapPicker,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: Text(hasPin ? 'Move Pin' : 'Drop Pin on Map',
                          style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.cutBlue,
                          side: const BorderSide(color: AppTheme.cutBlue),
                          padding: const EdgeInsets.symmetric(vertical: 10)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: OutlinedButton.icon(
                      onPressed: _fetchingGps ? null : _useCurrentLocation,
                      icon: _fetchingGps
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 16),
                      label: const Text('My Location',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.cutBlue,
                          side: const BorderSide(color: AppTheme.cutBlue),
                          padding: const EdgeInsets.symmetric(vertical: 10)),
                    )),
                  ]),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Post Update',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}

class _Sug {
  final String label;
  final double lat, lng;
  const _Sug({required this.label, required this.lat, required this.lng});
}
