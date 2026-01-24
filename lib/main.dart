import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sync_music/home_screen.dart';
import 'package:sync_music/onboarding_screen.dart';
import 'package:sync_music/theme/app_theme.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/services/notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Remote Config
    await RemoteConfigService().initialize();

    // Initialize Push Notifications (FCM)
    await NotificationService().initialize();

    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    debugPrint("Firebase initialized successfully");
  } catch (e) {
    debugPrint(
      "Firebase initialization failed (Expected if missing google-services.json): $e",
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
  runApp(PartyApp(showOnboarding: !onboardingSeen));
}

// ---------------- APP ROOT ----------------
class PartyApp extends StatelessWidget {
  final bool showOnboarding;
  const PartyApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sync Music',
      theme: AppTheme.darkTheme,
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
