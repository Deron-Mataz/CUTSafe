import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/user_provider.dart';
import '../../providers/alert_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with TickerProviderStateMixin {
  bool _sosActive = false;
  bool _sosLoading = false;
  String? _sosAddress;
  String? _sosAlertId;

  // EXTEND: Live SOS Tracking — pushes a fresh GPS fix to the active SOS
  // doc every 15 s so the marker on this app's map AND the admin dashboard
  // map moves in real time instead of staying frozen at trigger-time.
  Timer? _liveLocationTimer;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _ringAnim = Tween<double>(begin: 0.7, end: 1.6)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _liveLocationTimer?.cancel();
    super.dispose();
  }

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cannot dial $number')));
    }
  }

  Future<void> _onSOSTap() async {
    if (_sosActive) {
      await _markSafe();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.emergency, color: AppTheme.cutRed, size: 28),
          SizedBox(width: 10),
          Text('Send SOS?', style: TextStyle(fontSize: 18)),
        ]),
        content: const Text(
            'This will share your live location and alert nearby users.\n\nOnly use in a REAL emergency.',
            style: TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.cutMuted))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cutRed,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('YES, SEND SOS',
                  style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _CountdownDialog());
    if (proceed != true || !mounted) return;

    await _triggerSOS();
  }

  Future<void> _triggerSOS() async {
    setState(() => _sosLoading = true);
    try {
      final user = context.read<UserProvider>().user;
      if (user == null) {
        _err('You must be logged in.');
        return;
      }

      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null) {
        _err('Enable GPS and try again.');
        return;
      }

      final address = await LocationService.instance
              .reverseGeocode(pos.latitude, pos.longitude) ??
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';

      final alertId = await context.read<AlertProvider>().triggerSOS(
            uid: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            latitude: pos.latitude,
            longitude: pos.longitude,
            address: address,
          );
      if (alertId == null) {
        _err('Failed to send SOS. Try again.');
        return;
      }

      await NotificationService.instance
          .showSOSNotification(user.name, address);
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();

      if (mounted) {
        setState(() {
          _sosActive = true;
          _sosAddress = address;
          _sosAlertId = alertId;
        });
        _startLiveLocationUpdates(alertId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
                child: Text('SOS sent! Your live location is now tracked.')),
          ]),
          backgroundColor: AppTheme.cutRed,
          duration: Duration(seconds: 4),
        ));
      }
    } catch (e) {
      _err('SOS failed: $e');
    } finally {
      if (mounted) setState(() => _sosLoading = false);
    }
  }

  /// EXTEND: Live SOS Tracking. Every 15 seconds while the SOS is active,
  /// fetch a fresh GPS fix and push it to Firestore via
  /// FirebaseService.updateSOSLocation. Any client subscribed to
  /// alertsStream() (this app's map, the admin dashboard map) sees the
  /// marker move in real time — not a static snapshot.
  void _startLiveLocationUpdates(String alertId) {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final pos = await LocationService.instance.getCurrentPosition();
        if (pos == null) return;
        final address = await LocationService.instance
                .reverseGeocode(pos.latitude, pos.longitude) ??
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        await FirebaseService.instance
            .updateSOSLocation(alertId, pos.latitude, pos.longitude, address);
        if (mounted) setState(() => _sosAddress = address);
      } catch (_) {
        // Non-fatal — keep retrying on the next tick.
      }
    });
  }

  Future<void> _markSafe() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 26),
          SizedBox(width: 10),
          Text("I'm Safe"),
        ]),
        content: const Text(
            'This will mark your SOS as resolved and turn it green in the feed.',
            style: TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back',
                  style: TextStyle(color: AppTheme.cutMuted))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("I'M SAFE",
                  style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _sosLoading = true);
    try {
      _liveLocationTimer?.cancel();
      if (_sosAlertId != null)
        await context.read<AlertProvider>().markSOSSafe(_sosAlertId!);
      if (mounted) {
        setState(() {
          _sosActive = false;
          _sosAddress = null;
          _sosAlertId = null;
        });
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ You are marked as safe. Live tracking stopped.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ));
      }
    } catch (e) {
      _err('Could not update SOS: $e');
    } finally {
      if (mounted) setState(() => _sosLoading = false);
    }
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.cutRed));
  }

  @override
  Widget build(BuildContext context) {
    // EXTEND: emergency numbers now come from PlatformSettings (admin
    // dashboard Settings screen) instead of being hardcoded, so an admin
    // can add/edit/remove numbers from the backend and they appear here
    // instantly via the real-time settingsStream().
    final settings = context.watch<SettingsProvider>().settings;
    final numbers = settings.emergencyNumbers;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _SOSButton(
                active: _sosActive,
                loading: _sosLoading,
                address: _sosAddress,
                pulseAnim: _pulseAnim,
                ringAnim: _ringAnim,
                onTap: _sosLoading ? null : _onSOSTap),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _sosActive
                  ? Padding(
                      key: const ValueKey('safe_btn'),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ElevatedButton.icon(
                        onPressed: _sosLoading ? null : _markSafe,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        icon: const Icon(Icons.check_circle_outline,
                            color: Colors.white, size: 22),
                        label: const Text("I'M SAFE — Cancel SOS",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ))
                  : const SizedBox.shrink(key: ValueKey('safe_hidden')),
            ),
            const SizedBox(height: 12),
            const Text('EMERGENCY NUMBERS',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.cutMuted,
                    letterSpacing: 0.8)),
            const SizedBox(height: 12),
            for (var i = 0; i < numbers.length; i += 2) ...[
              Row(children: [
                Expanded(
                    child: _DialCard(
                        entry: numbers[i],
                        onTap: () => _call(numbers[i].number))),
                const SizedBox(width: 10),
                Expanded(
                    child: i + 1 < numbers.length
                        ? _DialCard(
                            entry: numbers[i + 1],
                            onTap: () => _call(numbers[i + 1].number))
                        : const SizedBox.shrink()),
              ]),
              if (i + 2 < numbers.length) const SizedBox(height: 10),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── Countdown dialog (unchanged behaviour) ────────────────────────
class _CountdownDialog extends StatefulWidget {
  const _CountdownDialog();
  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog>
    with SingleTickerProviderStateMixin {
  int _count = 5;
  Timer? _timer;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnim = Tween<double>(begin: 1.2, end: 0.8)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut));
    _vibrate();
    _scaleCtrl.forward(from: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _count--);
      _vibrate();
      _scaleCtrl.forward(from: 0);
      if (_count <= 0) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    });
  }

  void _vibrate() {
    HapticFeedback.heavyImpact();
    Future.delayed(
        const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppTheme.cutRed,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('SENDING SOS IN',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          const SizedBox(height: 16),
          AnimatedBuilder(
              animation: _scaleAnim,
              builder: (_, child) =>
                  Transform.scale(scale: _scaleAnim.value, child: child),
              child: Text('$_count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 80,
                      fontWeight: FontWeight.w900,
                      height: 1))),
          const SizedBox(height: 16),
          const Text('seconds',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 24),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop(false);
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('CANCEL',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              )),
        ]),
      );
}

class _SOSButton extends StatelessWidget {
  final bool active, loading;
  final String? address;
  final Animation<double> pulseAnim, ringAnim;
  final VoidCallback? onTap;
  const _SOSButton(
      {required this.active,
      required this.loading,
      this.address,
      required this.pulseAnim,
      required this.ringAnim,
      this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          SizedBox(
              width: 200,
              height: 200,
              child: Stack(alignment: Alignment.center, children: [
                if (active)
                  AnimatedBuilder(
                      animation: ringAnim,
                      builder: (_, __) => Opacity(
                          opacity: (1.6 - ringAnim.value).clamp(0.0, 0.6),
                          child: Container(
                              width: 200 * ringAnim.value,
                              height: 200 * ringAnim.value,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.cutRed
                                      .withValues(alpha: 0.25))))),
                if (active)
                  AnimatedBuilder(
                      animation: pulseAnim,
                      builder: (_, __) => Container(
                          width: 164 * pulseAnim.value,
                          height: 164 * pulseAnim.value,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.cutRed.withValues(alpha: 0.15)))),
                AnimatedBuilder(
                  animation: active ? pulseAnim : kAlwaysCompleteAnimation,
                  builder: (_, child) => Transform.scale(
                      scale: active ? pulseAnim.value : 1.0, child: child),
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? AppTheme.cutRed : Colors.white,
                        border: Border.all(color: AppTheme.cutRed, width: 3),
                        boxShadow: [
                          BoxShadow(
                              color: AppTheme.cutRed
                                  .withValues(alpha: active ? 0.5 : 0.2),
                              blurRadius: active ? 24 : 12,
                              spreadRadius: active ? 4 : 0)
                        ]),
                    child: loading
                        ? Center(
                            child: CircularProgressIndicator(
                                color: active ? Colors.white : AppTheme.cutRed,
                                strokeWidth: 3))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                Icon(Icons.emergency,
                                    size: 48,
                                    color: active
                                        ? Colors.white
                                        : AppTheme.cutRed),
                                const SizedBox(height: 6),
                                Text('SOS',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: active
                                            ? Colors.white
                                            : AppTheme.cutRed,
                                        letterSpacing: 2)),
                              ]),
                  ),
                ),
              ])),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: loading
                ? const Text('Please wait…',
                    key: ValueKey('ld'),
                    style: TextStyle(fontSize: 14, color: AppTheme.cutMuted))
                : active
                    ? Column(key: const ValueKey('ac'), children: [
                        const Text('SOS ACTIVE — Live Tracking',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.cutRed)),
                        const SizedBox(height: 4),
                        const Text('Your location updates every 15 seconds',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.cutMuted)),
                        if (address != null) ...[
                          const SizedBox(height: 6),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.location_on,
                                    size: 13, color: AppTheme.cutBlue),
                                const SizedBox(width: 4),
                                Flexible(
                                    child: Text(address!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.cutMuted))),
                              ]),
                        ],
                      ])
                    : const Text('Press to send an emergency alert',
                        key: ValueKey('id'),
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.cutMuted)),
          ),
        ]),
      );
}

class _DialCard extends StatelessWidget {
  final dynamic entry; // EmergencyNumber
  final VoidCallback onTap;
  const _DialCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
              color: AppTheme.cutBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppTheme.cutBlue.withValues(alpha: 0.3))),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: AppTheme.cutBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child:
                    const Icon(Icons.phone, color: AppTheme.cutBlue, size: 18)),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(entry.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTheme.cutBlue)),
                  Text(entry.number,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.cutMuted)),
                ])),
          ]),
        ),
      );
}
