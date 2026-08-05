import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';

/// FIX: previously main.dart routed straight to LoginScreen the instant
/// the widget tree built, because UserProvider's Firebase auth listener
/// resolves asynchronously — so LoginScreen was effectively acting as the
/// splash screen (flashing before snapping to Home once auth resolved).
/// This screen is now shown while `UserProvider.authResolved == false`.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.cutBlue,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 52, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text('CUT Safety',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Community Safety Platform',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 40),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
}
