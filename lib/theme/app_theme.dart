import 'package:flutter/material.dart';

class AppTheme {
  // Modern Palette: "Midnight & Neon"
  static const Color background = Color(0xFF0B0E14); // Deeper, cooler black
  static const Color surface = Color(0xFF151922);    // Slightly lighter for cards
  
  static const Color primary = Color(0xFF6C63FF);    // Electric Violet (Primary Action)
  static const Color secondary = Color(0xFF00D2FF);  // Cyan (Accents)
  static const Color accent = Color(0xFFFF2E63);     // Hot Pink (Alerts/Highlights)

  static const Color onBackground = Color(0xFFF0F2F5);
  static const Color onSurface = Color(0xFFB0B3B8);
  
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: accent,
        onSurface: onSurface,
        onPrimary: Colors.white,
      ),
      fontFamily: 'Roboto', // Default fallback, but consider adding GoogleFonts if possible
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: onBackground,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0, // Flat is modern
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // Softer corners
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: onSurface.withOpacity(0.4)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        prefixIconColor: onSurface.withOpacity(0.6),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
