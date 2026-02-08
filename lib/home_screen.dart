import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/providers/user_provider.dart';
import 'package:sync_music/services/notification_service.dart';
import 'package:sync_music/waiting_screen.dart';
import 'package:sync_music/qr_scanner_screen.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:sync_music/services/analytics_service.dart';
import 'package:sync_music/widgets/resume_party_card.dart';
import 'package:sync_music/settings_screen.dart';
import 'package:sync_music/explore_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  final AnalyticsService _analytics = AnalyticsService();

  final List<String> avatars = [
    "🎧",
    "🎸",
    "🎹",
    "🎤",
    "🎷",
    "🎺",
    "🥁",
    "🎻",
    "🎼",
    "🎙️",
    "📻",
    "🎵",
    "🌙",
    "☁️",
    "🌌",
    "💭",
    "🕯️",
    "⭐",
    "✨",
    "🔥",
    "⚡",
    "🎉",
    "🧢",
    "📼",
    "💿",
    "🖤",
    "🌵",
    "🧠",
    "📚",
    "🧐",
    "🎩",
    "😎",
    "😊",
    "🤝",
    "💬",
    "👀",
    "🕶️",
    "🌫️",
  ];

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    _initDeepLinks();

    // Log event to trigger In-App Messaging campaigns configured for Home Screen
    _analytics.logViewHomeScreen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().showWelcomeNotificationIfFirstTime();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userState = ref.read(userProvider);
      if (userState.username.isNotEmpty) {
        nameCtrl.text = userState.username;
      }
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    final appLink = await _appLinks.getInitialLink();
    if (appLink != null) _handleDeepLink(appLink);
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleDeepLink(uri),
    );
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'syncmusic') {
      String? code;
      if (uri.host == 'join' && uri.pathSegments.isNotEmpty) {
        code = uri.pathSegments.first;
      } else if (uri.host.isNotEmpty) {
        code = uri.host;
      }

      if (code != null && code.isNotEmpty) {
        setState(() {
          codeCtrl.text = code!.toUpperCase();
        });
        if (nameCtrl.text.trim().isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Auto-joining party: $code")));
          _joinParty();
        }
      }
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint("Failed to check for updates: $e");
    }
  }

  void _showProfileEditor({VoidCallback? onSave}) {
    final userState = ref.read(userProvider);
    final tempNameCtrl = TextEditingController(text: userState.username);
    
    // Find index of current avatar
    int initialIndex = avatars.indexOf(userState.avatar);
    if (initialIndex == -1) initialIndex = 0;
    
    final FixedExtentScrollController wheelController = FixedExtentScrollController(
      initialItem: initialIndex,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151922),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  left: 24,
                  right: 24,
                  top: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "EDIT PROFILE",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
              
                    // ---- HORIZONTAL SPIN WHEEL AVATAR SELECTOR ----
                    SizedBox(
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Selection Indicator (Glow)
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                              border: Border.all(
                                color: Theme.of(context).primaryColor.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
              
                          // The Wheel
                          RotatedBox(
                            quarterTurns: -1,
                            child: ListWheelScrollView.useDelegate(
                              controller: wheelController,
                              itemExtent: 80,
                              physics: const FixedExtentScrollPhysics(),
                              diameterRatio: 1.5,
                              perspective: 0.005,
                              onSelectedItemChanged: (index) {
                                HapticFeedback.selectionClick();
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: avatars.length,
                                builder: (context, index) {
                                  return RotatedBox(
                                    quarterTurns: 1,
                                    child: Center(
                                      child: Text(
                                        avatars[index],
                                        style: const TextStyle(fontSize: 44),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Swipe to change avatar",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
              
                    // Name Input
                    TextField(
                      controller: tempNameCtrl,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: "Your Name",
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                    ),
                    const SizedBox(height: 24),
              
                    ElevatedButton(
                      onPressed: () {
                        final name = tempNameCtrl.text.trim();
                        if (name.isEmpty) return;
              
                        final selectedAvatarIndex = wheelController.selectedItem;
                        final avatar = avatars[selectedAvatarIndex];
              
                        ref.read(userProvider.notifier).saveUser(name, avatar);
                        
                        Navigator.pop(context);
                        onSave?.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "SAVE CHANGES",
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _ensureNameSet(VoidCallback onSuccess) {
    if (nameCtrl.text.trim().isNotEmpty) {
      return true;
    }
    _showProfileEditor(onSave: onSuccess);
    return false;
  }

  void _createParty({
    String? name,
    bool isPublic = false,
    String mode = 'party',
  }) {
    if (!_ensureNameSet(
      () => _createParty(name: name, isPublic: isPublic, mode: mode),
    )) {
      return;
    }

    final username = nameCtrl.text.trim();
    final avatar = ref.read(userProvider).avatar;
    ref.read(userProvider.notifier).saveUser(username, avatar);

    ref
        .read(partyProvider.notifier)
        .createParty(
          username: username,
          avatar: avatar,
          name: name,
          isPublic: isPublic,
          mode: mode,
        );
  }

  void _showCreatePartyDialog() {
    if (!_ensureNameSet(_showCreatePartyDialog)) return;

    final partyNameCtrl = TextEditingController();
    bool isPublic = false;
    String mode = 'party';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151922),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  left: 24,
                  right: 24,
                  top: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- HEADER ----
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).primaryColor,
                                Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                          child: const Icon(
                            FontAwesomeIcons.rocket,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          "Launch Party",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ---- INPUT ----
                    TextField(
                      controller: partyNameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Party Name (Optional)",
                        labelStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ---- MODE ----
                    const Text(
                      "PARTY MODE",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildVisibilityOption(
                            context,
                            title: "Music",
                            subtitle: "Standard Party",
                            icon: FontAwesomeIcons.music,
                            isSelected: mode == 'party',
                            onTap: () => setState(() => mode = 'party'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildVisibilityOption(
                            context,
                            title: "Movie",
                            subtitle: "Watch Together",
                            icon: FontAwesomeIcons.clapperboard,
                            isSelected: mode == 'movie',
                            onTap: () => setState(() => mode = 'movie'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ---- TOGGLE ----
                    const Text(
                      "VISIBILITY",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildVisibilityOption(
                            context,
                            title: "Private",
                            subtitle: "Invite only",
                            icon: FontAwesomeIcons.lock,
                            isSelected: !isPublic,
                            onTap: () => setState(() => isPublic = false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildVisibilityOption(
                            context,
                            title: "Public",
                            subtitle: "Anyone can join",
                            icon: FontAwesomeIcons.earthAmericas,
                            isSelected: isPublic,
                            onTap: () => setState(() => isPublic = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ---- ACTION ----
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _createParty(
                          name: partyNameCtrl.text.trim().isEmpty
                              ? null
                              : partyNameCtrl.text.trim(),
                          isPublic: isPublic,
                          mode: mode,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        shadowColor: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.4),
                      ),
                      child: const Text(
                        "Launch Now",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVisibilityOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final color = isSelected
        ? Theme.of(context).primaryColor
        : Colors.white.withValues(alpha: 0.05);
    final borderColor = isSelected
        ? Theme.of(context).primaryColor
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : Colors.white54,
              size: 24,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? Colors.white70 : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _joinParty() {
    if (!_ensureNameSet(_joinParty)) return;

    final username = nameCtrl.text.trim();
    var code = codeCtrl.text.trim();

    if (code.toLowerCase().startsWith("syncmusic://join/")) {
      code = code.substring(17);
    }

    code = code.toUpperCase();
    if (code.isEmpty) return;

    final avatar = ref.read(userProvider).avatar;
    ref.read(userProvider.notifier).saveUser(username, avatar);

    ref
        .read(partyProvider.notifier)
        .joinParty(partyId: code, username: username, avatar: avatar);
  }

  Future<void> _scanQR() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && result is String) {
      var code = result;
      if (code.toLowerCase().startsWith("syncmusic://join/")) {
        code = code.substring(17);
      }
      setState(() {
        codeCtrl.text = code.toUpperCase();
      });
      _joinParty();
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    codeCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userState = ref.watch(userProvider);
    final partyState = ref.watch(partyProvider);

    ref.listen(partyProvider, (previous, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
      if (next.partyData != null && previous?.partyData != next.partyData) {
        if (ModalRoute.of(context)?.isCurrent != true) return;
        final socketId = ref.read(socketProvider).id;
        final isHost = next.isHost;
        _analytics.setUserProperties(
          userId: socketId ?? 'unknown',
          role: isHost ? 'host' : 'guest',
        );
        if (isHost) {
          _analytics.logPartyCreated(next.partyId ?? '');
        } else {
          _analytics.logPartyJoined(next.partyId ?? '');
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingScreen(
              party: next.partyData!,
              username: "${userState.avatar} ${userState.username}",
            ),
          ),
        );
      }
    });

    ref.listen(userProvider, (previous, next) {
      if (nameCtrl.text.isEmpty && next.username.isNotEmpty) {
        nameCtrl.text = next.username;
      }
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showProfileEditor,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  userState.avatar,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Hello, ${userState.username.isEmpty ? 'Guest' : userState.username}",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Ready to jam?",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.gear, color: Colors.white, size: 20),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.6),
            radius: 1.6,
            colors: [Color(0xFF1E2433), Color(0xFF0B0E14)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // 1. Resume Card (Top Priority)
                if (partyState.lastPartyId != null && !partyState.connecting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: ResumePartyCard(
                      partyId: partyState.lastPartyId!,
                      isHost: partyState.isHost,
                      onHostRejoin: () {
                        final username = nameCtrl.text.trim();
                        ref
                            .read(partyProvider.notifier)
                            .reconnectAsHost(
                              partyId: partyState.lastPartyId!,
                              username: username.isEmpty ? "Host" : username,
                              avatar: userState.avatar,
                            );
                      },
                      onGuestRejoin: () {
                        codeCtrl.text = partyState.lastPartyId!;
                        _joinParty();
                      },
                      onDismiss: () =>
                          ref.read(partyProvider.notifier).clearSession(),
                    ),
                  ),

                // 2. Main Hero Action (Host Party)
                Expanded(child: Center(child: _buildHeroCard(context))),

                const SizedBox(height: 24),

                // 3. Quick Actions Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildActionCard(
                        context,
                        title: "Explore",
                        subtitle: "Public Parties",
                        icon: FontAwesomeIcons.compass,
                        color: const Color(0xFF00D2FF),
                        onTap: () {
                          if (!_ensureNameSet(() {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ExploreScreen(),
                              ),
                            );
                          })) {
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ExploreScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildActionCard(
                        context,
                        title: "Scan QR",
                        subtitle: "Join Quickly",
                        icon: FontAwesomeIcons.qrcode,
                        color: const Color(0xFFFF2E63),
                        onTap: _scanQR,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 4. Join Section (Modern Pill)
                _buildJoinPill(context, theme),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.98, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: GestureDetector(
            onTapDown: (_) => HapticFeedback.selectionClick(),
            onTap: _showCreatePartyDialog,
            child: Container(
              height: 170,
              decoration: BoxDecoration(
                color: const Color(0xFF151922),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top accent bar
                    Container(height: 3, color: primary.withValues(alpha: 0.9)),

                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
                            Row(
                              children: [
                                Icon(
                                  FontAwesomeIcons.list,
                                  color: primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  "New Session",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  FontAwesomeIcons.arrowRight,
                                  color: Colors.white.withValues(alpha: 0.4),
                                  size: 18,
                                ),
                              ],
                            ),

                            const Spacer(),

                            // Title
                            const Text(
                              "Host a Party",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),

                            const SizedBox(height: 6),

                            // Subtitle
                            Text(
                              "Create a party and invite your friends who you vibe with.",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF151922),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinPill(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  hintText: "Enter Party Code...",
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _joinParty,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(FontAwesomeIcons.arrowRight, size: 18),
          ),
        ],
      ),
    );
  }
}
