import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/providers/user_provider.dart';
import 'package:sync_music/services/notification_service.dart';
import 'package:sync_music/waiting_screen.dart';
import 'package:sync_music/widgets/custom_button.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:sync_music/qr_scanner_screen.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:sync_music/services/analytics_service.dart';
import 'package:sync_music/widgets/settings_dialog.dart';
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
    // Music
    "🎧", "🎸", "🎹", "🎤", "🎷", "🎺", "🥁", "🎻", "🎼", "🎙️", "📻", "🎵",
    // Chill
    "🌙", "☁️", "🌌", "💭", "🕯️",
    // Performer
    "⭐", "✨", "🔥", "⚡", "🎉",
    // Creative / Indie
    "🧢", "📼", "💿", "🖤", "🌵",
    // Nerd
    "🧠", "📚", "🧐", "🎩",
    // Friendly
    "😎", "😊", "🤝", "💬",
    // Low-key
    "👀", "🕶️", "🌫️",
  ];

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    _initDeepLinks();
    
    // Trigger welcome notification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().showWelcomeNotificationIfFirstTime();
    });
    
    // Initialize name controller if provider already has data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userState = ref.read(userProvider);
      if (userState.username.isNotEmpty) {
        nameCtrl.text = userState.username;
      }
    });
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link
    final appLink = await _appLinks.getInitialLink();
    if (appLink != null) {
      _handleDeepLink(appLink);
    }

    // Listen for new links
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint("Deep Link Received: $uri");
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

        // Auto-join if name is already set
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

  void _createParty({String? name, bool isPublic = false}) {
    final username = nameCtrl.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }
    
    final avatar = ref.read(userProvider).avatar;
    ref.read(userProvider.notifier).saveUser(username, avatar);
    
    ref.read(partyProvider.notifier).createParty(
      username: username,
      avatar: avatar,
      name: name,
      isPublic: isPublic,
    );
  }

  void _showCreatePartyDialog() {
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }

    final partyNameCtrl = TextEditingController();
    bool isPublic = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text(
                "Host a Party",
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: partyNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Party Name (Optional)",
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text(
                      "Public Party",
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      "Visible in Explore",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: isPublic,
                    onChanged: (val) => setState(() => isPublic = val),
                    activeThumbColor: Theme.of(context).primaryColor,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _createParty(
                      name: partyNameCtrl.text.trim().isEmpty
                          ? null
                          : partyNameCtrl.text.trim(),
                      isPublic: isPublic,
                    );
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _joinParty() {
    final username = nameCtrl.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }

    final code = codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final avatar = ref.read(userProvider).avatar;
    ref.read(userProvider.notifier).saveUser(username, avatar);

    ref.read(partyProvider.notifier).joinParty(
      partyId: code,
      username: username,
      avatar: avatar,
    );
  }

  Future<void> _scanQR() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        codeCtrl.text = result;
      });
      _joinParty();
    }
  }

  void _showAvatarPicker() {
    final currentAvatar = ref.read(userProvider).avatar;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    "CHOOSE YOUR AVATAR",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 24),

                  /// 👇 SCROLLS
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                      itemCount: avatars.length,
                      itemBuilder: (context, index) {
                        final avatar = avatars[index];
                        final isSelected = avatar == currentAvatar;
                        return GestureDetector(
                          onTap: () {
                            ref.read(userProvider.notifier).saveUser(
                                  nameCtrl.text.trim(),
                                  avatar,
                                );
                            Navigator.pop(context);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).primaryColor.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Colors.transparent,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              avatar,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

    // Listeners for side effects
    ref.listen(partyProvider, (previous, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error.toString())),
        );
      }
      
      // Navigate to Waiting Screen on success
      if (next.partyData != null && previous?.partyData != next.partyData) {
        // Analytics
        final socketId = ref.read(socketProvider).id;
        final isHost = next.isHost;
        _analytics.setUserProperties(
            userId: socketId ?? 'unknown', 
            role: isHost ? 'host' : 'guest'
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
    
    // Auto-fill name if user provider loads it later
    ref.listen(userProvider, (previous, next) {
      if (nameCtrl.text.isEmpty && next.username.isNotEmpty) {
        nameCtrl.text = next.username;
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // App Title
                        const Text(
                          "Sync Music",
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Host or join a party and listen together",
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 40),
                        
                        // Resume Card
                        if (partyState.lastPartyId != null && !partyState.connecting)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: ResumePartyCard(
                              partyId: partyState.lastPartyId!,
                              isHost: partyState.isHost,
                              onHostRejoin: () {
                                final username = nameCtrl.text.trim();
                                final avatar = userState.avatar;
                                ref.read(partyProvider.notifier).reconnectAsHost(
                                  partyId: partyState.lastPartyId!,
                                  username: username.isEmpty ? "Host" : username,
                                  avatar: avatar,
                                );
                              },
                              onGuestRejoin: () {
                                codeCtrl.text = partyState.lastPartyId!;
                                _joinParty();
                              },
                              onDismiss: () async {
                                ref.read(partyProvider.notifier).clearSession();
                              },
                            ),
                          ),

                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                /// Profile row
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _showAvatarPicker,
                                      child: Semantics(
                                        label: "Select avatar",
                                        child: Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                            border: Border.all(
                                              color: theme.primaryColor
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            userState.avatar,
                                            style: const TextStyle(
                                              fontSize: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextField(
                                        controller: nameCtrl,
                                        textInputAction: TextInputAction.done,
                                        decoration: const InputDecoration(
                                          labelText: "Your name",
                                          hintText: "Enter display name",
                                          prefixIcon: Icon(
                                            Icons.person_outline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 32),

                                if (partyState.connecting)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                else ...[
                                  /// Primary action
                                  CustomButton(
                                    label: "Host a new party",
                                    icon: Icons.add_circle_outline,
                                    onPressed: _showCreatePartyDialog,
                                  ),

                                  const SizedBox(height: 16),

                                  /// Secondary action
                                  CustomButton(
                                    label: "Explore public parties",
                                    icon: Icons.explore_outlined,
                                    variant: ButtonVariant.secondary,
                                    onPressed: () {
                                      if (nameCtrl.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              "Please enter your name to continue",
                                            ),
                                          ),
                                        );
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

                                  const SizedBox(height: 32),

                                  /// Divider
                                  const Row(
                                    children: [
                                      Expanded(
                                        child: Divider(color: Colors.white24),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Text(
                                          "Or join with a code",
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(color: Colors.white24),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 24),

                                  /// Join section
                                  TextField(
                                    controller: codeCtrl,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      labelText: "Party code",
                                      hintText: "e.g. A9F2Q",
                                      prefixIcon: const Icon(
                                        Icons.vpn_key_outlined,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: "Scan QR code",
                                        icon: const Icon(Icons.qr_code_scanner),
                                        color: theme.primaryColor,
                                        onPressed: _scanQR,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  CustomButton(
                                    label: "Join party",
                                    icon: Icons.login_rounded,
                                    variant: ButtonVariant.secondary,
                                    onPressed: _joinParty,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            _TrustItem(
                              icon: Icons.lock_outline,
                              label: "Private",
                            ),
                            SizedBox(width: 12),
                            _TrustItem(
                              icon: Icons.person_off_outlined,
                              label: "No account",
                            ),
                            SizedBox(width: 12),
                            _TrustItem(
                              icon: Icons.money_off_outlined,
                              label: "Free",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                /// Settings
                Positioned(
                  top: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IconButton(
                      icon: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white70,
                      ),
                      tooltip: "Settings & support",
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => const SettingsDialog(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

class ResumePartyCard extends StatefulWidget {
  final String partyId;
  final bool isHost;
  final VoidCallback onHostRejoin;
  final VoidCallback onGuestRejoin;
  final VoidCallback onDismiss;

  const ResumePartyCard({
    super.key,
    required this.partyId,
    required this.isHost,
    required this.onHostRejoin,
    required this.onGuestRejoin,
    required this.onDismiss,
  });

  @override
  State<ResumePartyCard> createState() => _ResumePartyCardState();
}

class _ResumePartyCardState extends State<ResumePartyCard> {
  bool _disabled = false;

  void _run(VoidCallback action) {
    if (_disabled) return;
    setState(() => _disabled = true);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: _disabled ? 0.6 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              theme.primaryColor.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(
            color: theme.primaryColor.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.primaryColor.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// Header
              Row(
                children: [
                  const Icon(Icons.history, color: Colors.white70),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Resume Party",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: _disabled ? null : widget.onDismiss,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              /// Context
              Text(
                "Last session: ${widget.partyId}",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 16),

              /// Actions (DESIGN SYSTEM)
              Row(
                children: [
                  if (widget.isHost)
                    Expanded(
                      child: CustomButton(
                        label: "Host",
                        icon: Icons.campaign_outlined,
                        onPressed:
                            _disabled ? null : () => _run(widget.onHostRejoin),
                      ),
                    ),
                  if (widget.isHost) const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      label: "Join",
                      icon: Icons.login_rounded,
                      variant: ButtonVariant.secondary,
                      onPressed:
                          _disabled ? null : () => _run(widget.onGuestRejoin),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}