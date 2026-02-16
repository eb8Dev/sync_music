import 'package:flutter/material.dart';

class PartyThemes {
  static const List<LinearGradient> gradients = [
    // 1. Midnight
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0B0E14), Color(0xFF1A1F35)],
    ),
    // 2. Electric Violet
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2E0249), Color(0xFF6C63FF)],
    ),
    // 3. Ocean Depths
    LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF0F2027), Color(0xFF203A43)],
    ),
    // 4. Crimson Night
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF2C0404), Color(0xFF8A0808)],
    ),
    // 5. Cyberpunk
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF000000), Color(0xFF0B3D35)],
    ),
  ];
}
