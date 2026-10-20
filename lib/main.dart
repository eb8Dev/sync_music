import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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

    // Fire-and-forget wake-up ping. The server may be asleep (free hosting
    // sleeps when idle and takes 20-50s to wake). Kicking it off now means it's
    // warming up while the user is still on the home screen, so by the time they
    // create or join a party the socket connects quickly.
    _warmUpServer();

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

/// Pings the server's health endpoint so a sleeping instance starts waking
/// immediately on launch. Fire-and-forget: never blocks startup or throws.
void _warmUpServer() {
  try {
    final base = RemoteConfigService().getServerUrl();
    if (base.isEmpty) return;
    final url = Uri.parse("${base.replaceAll(RegExp(r'/$'), '')}/healthz");
    http
        .get(url)
        .timeout(const Duration(seconds: 60))
        .then((res) {
          debugPrint("Server warm-up ping: ${res.statusCode}");
        })
        .catchError((e) {
          debugPrint("Server warm-up ping failed (non-fatal): $e");
        });
  } catch (e) {
    debugPrint("Server warm-up ping skipped: $e");
  }
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
