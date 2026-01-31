import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/widgets/party_chat.dart';
import 'package:sync_music/widgets/party_controls.dart';
import 'package:sync_music/widgets/party_player.dart';
import 'package:sync_music/widgets/party_queue.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PartyScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> party;
  final String username;

  const PartyScreen({super.key, required this.party, required this.username});

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen>
    with SingleTickerProviderStateMixin {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  
  Timer? _debounce;
  List<yt.Video> searchResults = [];
  bool isSearching = false;

  late TabController _tabController;
  int _unreadMessages = 0;

  final StreamController<String> _reactionStreamCtrl = StreamController<String>.broadcast();

static const List<LinearGradient> _themes = [
    // 1. Midnight (The Original Reference)
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

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    
    // Initialize Notifier with passed data to avoid empty flash
    // Future.microtask(() => ref.read(partyStateProvider.notifier).init(widget.party));

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);

    // Subscribe to reactions
    final socket = ref.read(socketProvider);
    socket.on("REACTION", _onReactionReceived);
    socket.on("PARTY_ENDED", _onPartyEnded);
    socket.on("KICKED", _onKicked);
  }

  void _handleTabSelection() {
    if (_tabController.index == 1) {
      setState(() {
        _unreadMessages = 0;
      });
    }
  }

  void _onReactionReceived(data) {
    if (!mounted) return;
    _reactionStreamCtrl.add(data['emoji']);
  }

  void _onPartyEnded(data) {
    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(data['message'] ?? "Party Ended")),
    );
  }

  void _onKicked(data) {
    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("You have been kicked from the party.")),
    );
  }

  @override
  void dispose() {
    final socket = ref.read(socketProvider);
    socket.off("REACTION", _onReactionReceived);
    socket.off("PARTY_ENDED", _onPartyEnded);
    socket.off("KICKED", _onKicked);

    WakelockPlus.disable();
    searchCtrl.dispose();
    _reactionStreamCtrl.close();
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _ytService.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ---- SEARCH LOGIC ----
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.isEmpty) {
        setState(() => searchResults = []);
        return;
      }
      final results = await _ytService.searchVideos(query);
      if (mounted) {
        setState(() => searchResults = results);
      }
    });
  }

  void _addVideo(yt.Video video) {
    ref.read(partyStateProvider.notifier).addTrack(
          widget.party["id"],
          {
            "url": video.url,
            "title": video.title,
            "addedBy": widget.username,
          },
        );
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
  }

  // ---- HEADER ACTIONS ----
  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.party["id"]));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Party Code Copied!"),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _shareParty() {
    Share.share(
      "Join my music party! Code: ${widget.party['id']}\nLink: https://sync-music-server.onrender.com/join/${widget.party['id']}",
    );
  }

  void _changeTheme() {
    ref.read(partyStateProvider.notifier).changeTheme(widget.party["id"]);
  }

  void _showQRCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        content: SizedBox(
          width: 200,
          height: 200,
          child: QrImageView(
            data: "syncmusic://join/${widget.party['id']}",
            version: QrVersions.auto,
            size: 200.0,
          ),
        ),
      ),
    );
  }

  void _leaveParty() {
    Navigator.pop(context);
  }

  void _showMembersList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final members = ref.watch(partyStateProvider.select((s) => s.members));
            final isHost = ref.watch(partyProvider.select((s) => s.isHost));
            final socket = ref.read(socketProvider);
            
            return Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "MEMBERS",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: members.isEmpty
                        ? const Center(
                            child: Text(
                              "Loading members...",
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: members.length,
                            itemBuilder: (context, index) {
                              final member = members[index];
                              final isMe = member['id'] == socket.id;
                              final isMemberHost = member['isHost'] == true;
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Colors.white10,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    member['avatar'] ?? "👤",
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                                title: Text(
                                  "${member['username'] ?? 'Guest'} ${isMe ? '(You)' : ''}",
                                  style: const TextStyle(color: Colors.white),
                                ),
                                subtitle: isMemberHost
                                    ? const Text(
                                        "HOST",
                                        style: TextStyle(
                                          color: Color(0xFFBB86FC),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                                trailing: isHost && !isMemberHost
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          ref.read(partyStateProvider.notifier).kickUser(
                                            widget.party['id'],
                                            member['id'],
                                          );
                                        },
                                      )
                                    : null,
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

  void _sendReaction(String emoji) {
     ref.read(partyStateProvider.notifier).sendReaction(widget.party["id"], emoji);
     _reactionStreamCtrl.add(emoji); // Local feedback immediate
  }

  // ---- BUILD HELPERS ----
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.transparent,
      child: Column(
        children: [
          // ---- SEARCH RESULTS ----
          if (searchCtrl.text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
              ),
              child: searchResults.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          "No videos found",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.4),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: searchResults.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withOpacity(0.05),
                      ),
                      itemBuilder: (_, i) {
                        final video = searchResults[i];
                        return InkWell(
                          onTap: () => _addVideo(video),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    video.thumbnails.lowResUrl,
                                    width: 36,
                                    height: 36,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    video.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

          // ---- SEARCH INPUT ----
          TextField(
            controller: searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Search YouTube",
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: Colors.white.withOpacity(0.4),
                size: 18,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ["🔥", "❤️", "🎉", "😂", "👋", "💃"].map((emoji) {
          return InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _sendReaction(emoji),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Top-level selects for Layout
    final themeIndex = ref.watch(partyStateProvider.select((s) => s.themeIndex));
    final isDisconnected = ref.watch(partyStateProvider.select((s) => s.isDisconnected));
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    
    // Unread messages logic
    ref.listen(partyStateProvider.select((s) => s.messages.length), (prev, next) {
        if (_tabController.index != 1) {
           final diff = next - (prev ?? 0);
           if (diff > 0) {
              setState(() {
                 _unreadMessages += diff;
              });
           }
        }
    });

    // Force exit if global party state clears (e.g. Party Ended)
    ref.listen(partyProvider, (prev, next) {
      if (prev?.partyId != null && next.partyId == null) {
        if (mounted) {
           Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    });

    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      body: FloatingEmojis(
        reactionStream: _reactionStreamCtrl.stream,
        child: Container(
          decoration: BoxDecoration(gradient: _themes[themeIndex]),
          child: SafeArea(
            child: Column(
              children: [
                 // ---- HEADER ----
                 Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Party Code & Connection
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isDisconnected)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 8, 
                                      height: 8, 
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                                    ),
                                    const SizedBox(width: 6),
                                    Text("Reconnecting...", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            GestureDetector(
                              onTap: _copyCode,
                              child: Row(
                                children: [
                                  Text(
                                    widget.party["id"],
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.copy_rounded, size: 14, color: Colors.white.withOpacity(0.5)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _showMembersList,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.people_alt_rounded, size: 12, color: Theme.of(context).primaryColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      "$partySize active",
                                      style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Actions
                        Row(
                          children: [
                            _HeaderIconButton(icon: Icons.share_rounded, onTap: _shareParty),
                            const SizedBox(width: 8),
                            if (isHost) ...[
                              _HeaderIconButton(icon: Icons.palette_rounded, onTap: _changeTheme),
                              const SizedBox(width: 8),
                              _HeaderIconButton(icon: Icons.qr_code_rounded, onTap: _showQRCode),
                              const SizedBox(width: 8),
                            ],
                            _RoleChip(isHost: isHost),
                          ],
                        ),
                      ],
                    ),
                 ),

                 // ---- PLAYER & CONTROLS ----
                 AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                      height: isKeyboardOpen ? 0 : null,
                      child: Column(
                        children: [
                           Padding(
                             padding: const EdgeInsets.symmetric(horizontal: 16),
                             child: PartyPlayer(partyId: widget.party['id']),
                           ),
                           const SizedBox(height: 10),
                           _buildReactions(),
                           const SizedBox(height: 10),
                           PartyControls(partyId: widget.party['id'], onLeave: _leaveParty),
                           const SizedBox(height: 12),
                        ],
                      ),
                    ),
                 ),

                 // ---- TABS ----
                 TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorColor: Theme.of(context).primaryColor,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white.withOpacity(0.45),
                    indicatorWeight: 3,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    tabs: [
                      const Tab(text: "QUEUE"),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("CHAT"),
                            if (_unreadMessages > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _unreadMessages > 9 ? "9+" : "$_unreadMessages",
                                  style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                 const SizedBox(height: 6),

                 // ---- TAB CONTENT ----
                 Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                         const _KeepAliveWrapper(
                           child: Column(
                             children: [
                               Expanded(child: PartyQueue(partyId: "")), // Pass dummy or fix constructor usage?
                               // Wait, PartyQueue needs partyId. 
                               // Actually, I can just use the widget.party['id'] from state.
                               // Let's check how it was called before.
                             ],
                           ),
                         ),
                         // ...
                      ],
                    ),
                 ),
                 
      // Wait, let's look at the existing code to see how it's called.
      // Existing:
      // Expanded(child: PartyQueue(partyId: widget.party['id'])),
      // _buildSearchBar(),
      
      // So:
                 // ---- TAB CONTENT ----
                 Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                         _KeepAliveWrapper(
                           child: Column(
                             children: [
                               Expanded(child: PartyQueue(partyId: widget.party['id'])),
                               _buildSearchBar(),
                             ],
                           ),
                         ),
                         _KeepAliveWrapper(
                           child: PartyChat(partyId: widget.party['id'], username: widget.username),
                         ),
                      ],
                    ),
                 ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final bool isHost;

  const _RoleChip({required this.isHost});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isHost ? const Color(0xFF6C63FF) : const Color(0xFF00D2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isHost ? "HOST" : "GUEST",
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
