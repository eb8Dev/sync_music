import 'package:flutter/material.dart';
import 'package:sync_music/home_screen.dart';
import 'package:sync_music/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PartyApp());
}

// ---------------- APP ROOT ----------------
class PartyApp extends StatelessWidget {
  const PartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sync Music',
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
