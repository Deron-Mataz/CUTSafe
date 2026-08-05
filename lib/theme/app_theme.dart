import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CUT brand colours and app-wide theme definitions.
/// Primary  : CUT Blue  #0033A0
/// Accent   : CUT Red   #D62828
/// Surface  : White     #FFFFFF
class AppTheme {
  AppTheme._();

  // ── Brand palette ──────────────────────────────────────────────
  static const Color cutBlue = Color(0xFF0033A0);
  static const Color cutRed = Color(0xFFD62828);
  static const Color cutWhite = Color(0xFFFFFFFF);
  static const Color cutGrey = Color(0xFFF5F6FA);
  static const Color cutDark = Color(0xFF1A1A2E);
  static const Color cutMuted = Color(0xFF8A8FAB);
  static const Color cutBorder = Color(0xFFE4E6F0);

  // ── Light theme ────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',

      colorScheme: const ColorScheme.light(
        primary: cutBlue,
        onPrimary: cutWhite,
        secondary: cutRed,
        onSecondary: cutWhite,
        surface: cutWhite,
        onSurface: cutDark,
        surfaceContainerHighest: cutGrey,
        outline: cutBorder,
      ),

      scaffoldBackgroundColor: cutGrey,

      // App bar
      appBarTheme: const AppBarTheme(
        backgroundColor: cutBlue,
        foregroundColor: cutWhite,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: cutWhite),
        actionsIconTheme: IconThemeData(color: cutWhite),
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cutWhite,
          letterSpacing: 0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),

      // Bottom nav
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cutWhite,
        selectedItemColor: cutBlue,
        unselectedItemColor: cutMuted,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cutBlue,
          foregroundColor: cutWhite,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cutBlue,
          side: const BorderSide(color: cutBlue, width: 1.5),
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cutWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cutBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cutBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cutBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cutRed, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: cutMuted, fontSize: 14),
        labelStyle: const TextStyle(color: cutMuted, fontSize: 14),
      ),

      // Card
      cardTheme: CardThemeData(
        color: cutWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: cutBorder),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Divider
      dividerTheme:
          const DividerThemeData(color: cutBorder, thickness: 1, space: 0),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: cutGrey,
        selectedColor: cutBlue.withValues(alpha: 0.15),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        side: const BorderSide(color: cutBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // FIX: this was returning `null`, which silently made MaterialApp fall
  // back to its default Material3 theme (white app bar, white nav bar,
  // purple seed colour) — this was the entire cause of the "theme
  // destroyed" bug. It must return the actual lightTheme.
  static ThemeData get light => lightTheme;
}
