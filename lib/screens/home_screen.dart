import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'alerts/alerts_screen.dart';
import 'groups/groups_screen.dart';
import 'map/map_screen.dart';
import 'emergency/emergency_screen.dart';
import 'profile/profile_screen.dart';
import 'dashboard/security_home_screen.dart';
import '../providers/user_provider.dart';

/// Root post-login destination for every role.
///
/// Role-based routing (Requirement #1): after login, HomeScreen reads the
/// signed-in user's role from Firebase (via UserProvider, which already
/// mirrors it live) and hands off to the correct experience:
///   • security        → SecurityHomeScreen (new dashboard-first shell)
///   • user (default)  → the existing Student/Staff experience, unchanged
///
/// Administrator accounts are deliberately left on the `user` branch below
/// (task requirement: "Administrator functionality remains in the Admin
/// Dashboard and must not be exposed in the mobile application" — for this
/// phase only User and Security reach the app at all). Enabling a future
/// Administrator mobile experience only requires adding one more branch
/// here (e.g. `if (role == 'administrator') return const AdminHomeScreen();`)
/// — no changes to navigation, auth, or existing screens required.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;
  final Set<int> _built = {0};

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const AlertsScreen();
      case 1:
        return const MapScreen();
      case 2:
        return const EmergencyScreen();
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
    // Role-based branch — see class doc comment above.
    final role = context.watch<UserProvider>().user?.role;
    if (role == 'security') return SecurityHomeScreen();

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
            icon: Icon(Icons.emergency_outlined),
            activeIcon: Icon(Icons.emergency),
            label: 'Emergency',
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
