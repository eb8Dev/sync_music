import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sync_music/home_screen.dart';
import 'package:sync_music/onboarding_screen.dart';
import 'package:sync_music/theme/app_theme.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/services/notification_service.dart';
import 'package:sync_music/providers/socket_provider.dart';
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
  runApp(ProviderScope(child: PartyApp(showOnboarding: !onboardingSeen)));
}

// ---------------- APP ROOT ----------------
class PartyApp extends ConsumerStatefulWidget {
  final bool showOnboarding;
  const PartyApp({super.key, required this.showOnboarding});

  @override
  ConsumerState<PartyApp> createState() => _PartyAppState();
}

class _PartyAppState extends ConsumerState<PartyApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint("App resumed: Checking socket connection...");
      try {
        // We defer the read slightly to ensure the provider scope is ready if needed,
        // though typically it is available here.
        final socket = ref.read(socketProvider);
        if (!socket.connected) {
          debugPrint("Socket disconnected. Attempting to reconnect...");
          socket.connect();
        } else {
          debugPrint("Socket is already connected.");
        }
      } catch (e) {
        debugPrint("Error handling resume socket check: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,

      debugShowCheckedModeBanner: false,
      title: 'Sync Music',
      theme: AppTheme.darkTheme,
      home: widget.showOnboarding
          ? const OnboardingScreen()
          : const HomeScreen(),
    );
  }
}

// flutter build apk --target-platform android-arm64 --split-per-ab
// flutter build appbundle --release
