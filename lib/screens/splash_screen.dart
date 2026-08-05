import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'auth/login_screen.dart';
import 'home_screen.dart';
import 'terms_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    // Give the splash at least 2 seconds, then decide where to go
    Future.delayed(const Duration(seconds: 2), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;

    // Check if the user has already accepted the terms
    final prefs = await SharedPreferences.getInstance();
    final hasAccepted = prefs.getBool(kTermsAcceptedKey) ?? false;

    if (!mounted) return;

    if (!hasAccepted) {
      // First-time user → show Terms screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TermsScreen()),
      );
      return;
    }

    // Returning user → go straight to Home or Login
    final authed = FirebaseService.instance.firebaseUser != null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => authed ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.cutBlue,
        body: FadeTransition(
          opacity: _fade,
          child: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 58, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text('CUT Safety',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text('Community Safety Platform',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 14)),
              const SizedBox(height: 48),
              const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            ]),
          ),
        ),
      );
}
