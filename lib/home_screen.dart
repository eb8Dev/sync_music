import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sync_music/waiting_screen.dart';
import 'package:sync_music/widgets/custom_button.dart';
import 'package:sync_music/widgets/glass_card.dart';

const SERVER_URL = "https://sync-music-server.onrender.com";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late IO.Socket socket;
  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();

  bool connecting = false;

  // Persisted session info
  String? lastPartyId;
  bool isHost = false;

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  void _initSocket() {
    socket = IO.io(SERVER_URL, {
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

      setState(() {
        connecting = false;
        lastPartyId = data["id"];
        isHost = data["isHost"] == true;
      });

      final username = nameCtrl.text.trim().isEmpty
          ? "Guest"
          : nameCtrl.text.trim();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingScreen(
            socket: socket,
            party: Map<String, dynamic>.from(data),
            username: username,
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

  void _createParty() {
    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first")),
      );
      return;
    }
    setState(() => connecting = true);
    // Even if server ignores it, we send it for future-proofing or if server is updated
    socket.emit("CREATE_PARTY", {"username": nameCtrl.text.trim()});
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

    socket.emit("JOIN_PARTY", code);
  }

  @override
  void dispose() {
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
            child: Center(
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
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                labelText: "YOUR NAME",
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 24),

                            if (connecting)
                              const CircularProgressIndicator()
                            else ...[
                              CustomButton(
                                label: "HOST NEW PARTY",
                                icon: Icons.add_circle_outline,
                                onPressed: _createParty,
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
                                decoration: const InputDecoration(
                                  labelText: "PARTY CODE",
                                  prefixIcon: Icon(Icons.vpn_key_outlined),
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
          ),
        ],
      ),
    );
  }
}