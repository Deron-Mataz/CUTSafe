import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// EXTEND: Backend SettingsController exposes MaintenanceMode +
/// MaintenanceMessage. Wrap MaterialApp's home/builder with this gate so the
/// entire app instantly blocks all interaction when an admin flips the
/// toggle in the dashboard, and instantly restores when turned off —
/// driven by a real-time Firestore listener (SettingsProvider), not a
/// one-time check at launch.
class MaintenanceGate extends StatelessWidget {
  final Widget child;
  const MaintenanceGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (!settings.isMaintenance) return child;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppTheme.cutBlue,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.build_circle_outlined,
                        size: 64, color: Colors.white),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Under Maintenance',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    settings.settings.maintenanceMessage?.isNotEmpty == true
                        ? settings.settings.maintenanceMessage!
                        : 'CUT Safety is currently undergoing scheduled '
                            'maintenance. Please check back shortly.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.emergency, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'In an emergency, call SAPS 10111 directly',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
