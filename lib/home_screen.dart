import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:app_links/app_links.dart';
import 'package:sync_music/waiting_screen.dart';
import 'package:sync_music/widgets/custom_button.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_music/qr_scanner_screen.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:sync_music/services/analytics_service.dart';
import 'package:sync_music/widgets/settings_dialog.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/explore_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late IO.Socket socket;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  final AnalyticsService _analytics = AnalyticsService();
  final RemoteConfigService _remoteConfig = RemoteConfigService();

  bool connecting = false;
  String selectedAvatar = "🎧";
  final List<String> avatars = ["🎧", "🎸", "🎹", "🎤", "🎷", "🎺", "🥁", "🎻", "🎼", "🎙️", "📻", "🎵"];

  // Persisted session info
  String? lastPartyId;
  bool isHost = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    _loadSession();
    _initSocket();
    _initDeepLinks();
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
      // Handle "syncmusic://join/CODE" or "syncmusic://CODE"
      // If host is part of path, e.g. "syncmusic://join/CODE" -> host=join, path segments=[CODE]
      // If "syncmusic://CODE" -> host=CODE
      
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
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Auto-joining party: $code")),
          );
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

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      lastPartyId = prefs.getString("lastPartyId");
      isHost = prefs.getBool("isHost") ?? false;
      selectedAvatar = prefs.getString("userAvatar") ?? avatars[0];
      final savedName = prefs.getString("username");
      if (savedName != null) {
        nameCtrl.text = savedName;
      }
    });
  }

  Future<void> _saveSession(String partyId, bool host, String username, String avatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("lastPartyId", partyId);
    await prefs.setBool("isHost", host);
    await prefs.setString("username", username);
    await prefs.setString("userAvatar", avatar);
  }

  void _initSocket() {
    final serverUrl = _remoteConfig.getServerUrl();
    debugPrint("Connecting to: $serverUrl");
    
    socket = IO.io(serverUrl, {
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1000,
    });

    // When socket connects or reconnects
    socket.onConnect((_) {
      debugPrint("Socket connected: ${socket.id}");

      // Reclaim host role if needed
      if (lastPartyId != null && isHost == true) {
        socket.emit("RECONNECT_AS_HOST", {"partyId": lastPartyId});
      }
    });

    // Server sends party state after create/join
    socket.on("PARTY_STATE", (data) {
      debugPrint("PARTY_STATE received: $data");

      final partyId = data["id"];
      final hostStatus = data["isHost"] == true;
      final username =
          nameCtrl.text.trim().isEmpty ? "Guest" : nameCtrl.text.trim();
      
      // Log Analytics
      if (hostStatus) {
        _analytics.logPartyCreated(partyId);
      } else {
        _analytics.logPartyJoined(partyId);
      }
      _analytics.setUserProperties(userId: socket.id ?? 'unknown', role: hostStatus ? 'host' : 'guest');

      setState(() {
        connecting = false;
        lastPartyId = partyId;
        isHost = hostStatus;
      });

      _saveSession(partyId, hostStatus, username, selectedAvatar);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => WaitingScreen(
                socket: socket,
                party: Map<String, dynamic>.from(data),
                username: "$selectedAvatar $username",
              ),
        ),
      );
    });

    socket.on("ERROR", (msg) {
      debugPrint("SERVER ERROR: $msg");
      setState(() => connecting = false);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    });
  }

  void _createParty({String? name, bool isPublic = false}) {
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }
    setState(() => connecting = true);
    
    socket.emit("CREATE_PARTY", {
      "username": nameCtrl.text.trim(),
      "avatar": selectedAvatar,
      "name": name,
      "isPublic": isPublic,
    });
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
              title: const Text("Host a Party", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: partyNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Party Name (Optional)",
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text("Public Party", style: TextStyle(color: Colors.white)),
                    subtitle: const Text("Visible in Explore", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: isPublic,
                    onChanged: (val) => setState(() => isPublic = val),
                    activeColor: Theme.of(context).primaryColor,
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
                      name: partyNameCtrl.text.trim().isEmpty ? null : partyNameCtrl.text.trim(),
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
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }

    final code = codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => connecting = true);

    socket.emit("JOIN_PARTY", {
      "partyId": code,
      "username": nameCtrl.text.trim(),
      "avatar": selectedAvatar,
    });
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
      // Optionally auto-join:
      // _joinParty();
    }
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: avatars.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      setState(() => selectedAvatar = avatars[index]);
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: selectedAvatar == avatars[index]
                            ? Theme.of(context).primaryColor.withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedAvatar == avatars[index]
                              ? Theme.of(context).primaryColor
                              : Colors.transparent,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        avatars[index],
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    codeCtrl.dispose();
    nameCtrl.dispose();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "SYNC MUSIC",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 48),

                        GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _showAvatarPicker,
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Theme.of(context).primaryColor.withOpacity(0.5),
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          selectedAvatar,
                                          style: const TextStyle(fontSize: 30),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: TextField(
                                        controller: nameCtrl,
                                        decoration: const InputDecoration(
                                          labelText: "YOUR NAME",
                                          prefixIcon: Icon(Icons.person_outline),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                if (connecting)
                                  const CircularProgressIndicator()
                                else ...[
                                  CustomButton(
                                    label: "HOST NEW PARTY",
                                    icon: Icons.add_circle_outline,
                                    onPressed: _showCreatePartyDialog,
                                  ),
                                  const SizedBox(height: 24),

                                  CustomButton(
                                    label: "EXPLORE PUBLIC PARTIES",
                                    icon: Icons.explore,
                                    isPrimary: false,
                                    onPressed: () {
                                      if (nameCtrl.text.trim().isEmpty) {
                                         ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Please enter your name first")),
                                        );
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ExploreScreen(
                                            socket: socket,
                                            username: nameCtrl.text.trim(),
                                            avatar: selectedAvatar,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 24),

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
                                          "OR JOIN",
                                          style: TextStyle(color: Colors.white54),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(color: Colors.white24),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),

                                  TextField(
                                    controller: codeCtrl,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      labelText: "PARTY CODE",
                                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.qr_code_scanner),
                                        color: Theme.of(context).primaryColor,
                                        onPressed: _scanQR,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  CustomButton(
                                    label: "JOIN PARTY",
                                    isPrimary: false,
                                    icon: Icons.login,
                                    onPressed: _joinParty,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: IconButton(
                      icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                      tooltip: "Settings & Support",
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => const SettingsDialog(),
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