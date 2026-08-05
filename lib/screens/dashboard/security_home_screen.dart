import 'package:flutter/material.dart';
import '../groups/groups_screen.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';
import 'security_dashboard_screen.dart';
import 'security_alerts_screen.dart';

/// Security-role equivalent of HomeScreen.
///
/// Reuses GroupsScreen, MapScreen and ProfileScreen exactly as the
/// Student/Staff experience does (per the brief: "reuse and adapt the
/// existing screens wherever appropriate"). Only two destinations are
/// Security-specific: the new Dashboard (replaces Alerts as the home tab)
/// and a dedicated Security Alerts page (task #5 — Alerts is no longer
/// the Security home screen, and gets its own Security-flavoured page).
///
/// Emergency (personal SOS) is intentionally NOT a bottom-nav destination
/// here — a 6th nav item would break the existing fixed 5-item
/// BottomNavigationBar styling. It remains fully reused: it's one tap away
/// from the Dashboard's quick actions, so Security personnel keep the same
/// SOS capability as any other user.
class SecurityHomeScreen extends StatefulWidget {
  const SecurityHomeScreen({super.key});
  @override
  State<SecurityHomeScreen> createState() => _SecurityHomeScreenState();
}

class _SecurityHomeScreenState extends State<SecurityHomeScreen> {
  int _idx = 0;
  final Set<int> _built = {0};

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const SecurityDashboardScreen();
      case 1:
        return const SecurityAlertsScreen();
      case 2:
        return const MapScreen();
      case 3:
        return const GroupsScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: List.generate(5, (i) {
          if (!_built.contains(i)) return const SizedBox.shrink();
          return Offstage(
            offstage: i != _idx,
            child: TickerMode(
              enabled: i == _idx,
              child: _page(i),
            ),
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() {
          _built.add(i);
          _idx = i;
        }),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_outlined),
            activeIcon: Icon(Icons.warning_amber_rounded),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            activeIcon: Icon(Icons.group),
            label: 'Groups',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
