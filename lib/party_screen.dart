import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/widgets/floating_emojis.dart';
import 'package:sync_music/widgets/generate_party_image.dart';
import 'package:sync_music/widgets/party_chat.dart';
import 'package:sync_music/widgets/party_lyrics.dart';
import 'package:sync_music/widgets/party_player.dart';
import 'package:sync_music/widgets/party_queue.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_music/widgets/exit_confirmation_dialog.dart';
import 'package:sync_music/party_ended_screen.dart';
import 'package:sync_music/widgets/add_to_playlist_sheet.dart';
import 'package:sync_music/widgets/playlist_import_sheet.dart';
import 'package:sync_music/party_kicked_screen.dart';

class PartyScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> party;
  final String username;

  const PartyScreen({super.key, required this.party, required this.username});

  @override
  ConsumerState<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends ConsumerState<PartyScreen> {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  final GlobalKey<PartyPlayerState> _playerKey = GlobalKey<PartyPlayerState>();

  Timer? _debounce;
  List<yt.Video> searchResults = [];
  bool isSearching = false;
  bool isPlaylistDetected = false;
  bool _canPop = false;

  int _selectedIndex = 0;
  int _unreadMessages = 0;

  final StreamController<String> _reactionStreamCtrl =
      StreamController<String>.broadcast();

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

    // Subscribe to reactions
    final socket = ref.read(socketProvider);
    socket.on("REACTION", _onReactionReceived);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // If Chat tab (index 2) is selected, clear unread
      if (_selectedIndex == 2) {
        _unreadMessages = 0;
      }
    });
  }

  void _onReactionReceived(data) {
    if (!mounted) return;
    _reactionStreamCtrl.add(data['emoji']);
  }

  @override
  void dispose() {
    final socket = ref.read(socketProvider);
    socket.off("REACTION", _onReactionReceived);

    WakelockPlus.disable();
    searchCtrl.dispose();
    _reactionStreamCtrl.close();
    _ytService.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ---- SEARCH LOGIC ----
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Reset detection
    if (isPlaylistDetected) {
      setState(() => isPlaylistDetected = false);
    }

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.isEmpty) {
        setState(() => searchResults = []);
        return;
      }

      // Check for Playlist Link
      if (query.contains("list=") && query.contains("youtube.com")) {
        setState(() {
          isPlaylistDetected = true;
          searchResults = []; // Clear video results to show import button
        });
        return;
      }

      final results = await _ytService.searchVideos(query);
      if (mounted) {
        setState(() => searchResults = results);
      }
    });
  }

  Future<void> _importPlaylist() async {
    final url = searchCtrl.text.trim();
    if (url.isEmpty) return;

    // Unfocus and show loading state
    FocusScope.of(context).unfocus();
    setState(() {
      isSearching = true; // Use searching flag to show spinner if needed
      isPlaylistDetected = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Importing top 15 songs from playlist...")),
    );

    try {
      final videos = await _ytService.getPlaylistVideos(url);

      // Add them one by one (or batch if backend supported it, but loop is fine for now)
      int count = 0;
      for (var video in videos) {
        // Check playable logic? Maybe skip for speed, rely on later check
        ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
          "url": video.url,
          "title": video.title,
          "addedBy": widget.username,
        });
        count++;
        // Small delay to prevent flooding if socket is sensitive (optional)
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully added $count songs!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to import playlist.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
          searchCtrl.clear();
        });
      }
    }
  }

  void _addVideo(yt.Video video) {
    ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
      "url": video.url,
      "title": video.title,
      "addedBy": widget.username,
    });
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

  void _shareParty() async {
    final serverUrl = RemoteConfigService().getServerUrl();
    final partyCode = widget.party["id"];
    final link = "$serverUrl/join/$partyCode";

    // Generate the image
    final imageFile = await generatePartyImage(partyCode);

    // Prepare ShareParams
    final params = ShareParams(
      files: [XFile(imageFile.path)],
      text:
          "Join my music party on Sync Music! Use CODE: $partyCode.\nOr click on this link: $link to join.",
      title: "Join Sync Music Party",
    );

    // Share
    final result = await SharePlus.instance.share(params);

    if (result.status == ShareResultStatus.dismissed) {
      print("User dismissed sharing.");
    }
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(
            partyStateProvider.select((s) => s.settings),
          );
          final themeIndex = ref.watch(
            partyStateProvider.select((s) => s.themeIndex),
          );

          void update(String key, bool value) {
            final newSettings = Map<String, bool>.from(settings);
            newSettings[key] = value;
            ref
                .read(partyStateProvider.notifier)
                .updateSettings(widget.party['id'], newSettings);
          }

          void applyPreset(String type) {
            Map<String, bool> newSettings = {};
            if (type == 'host') {
              newSettings = {
                "guestControls": false,
                "guestQueueing": false,
                "voteSkip": false,
              };
            } else if (type == 'guest') {
              newSettings = {
                "guestControls": false,
                "guestQueueing": true,
                "voteSkip": true,
              };
            } else if (type == 'collab') {
              newSettings = {
                "guestControls": true,
                "guestQueueing": true,
                "voteSkip": false,
              };
            }
            ref
                .read(partyStateProvider.notifier)
                .updateSettings(widget.party['id'], newSettings);
          }

          return Container(
            padding: const EdgeInsets.all(24.0),
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Party Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                // ---- PRESETS ----
                const Text(
                  "PRESETS",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _PresetCard(
                        icon: FontAwesomeIcons.shieldHalved,
                        label: "Host Mode",
                        color: Colors.redAccent,
                        onTap: () => applyPreset('host'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PresetCard(
                        icon: FontAwesomeIcons.checkToSlot,
                        label: "Guest Mode",
                        color: Colors.blueAccent,
                        onTap: () => applyPreset('guest'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PresetCard(
                        icon: FontAwesomeIcons.handshake,
                        label: "Collab",
                        color: Colors.greenAccent,
                        onTap: () => applyPreset('collab'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ---- CONTROLS ----
                const Text(
                  "PERMISSIONS",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _SwitchTile(
                  label: "Guest Controls",
                  subtitle: "Allow guests to Play, Pause & Seek",
                  value: settings["guestControls"] ?? false,
                  onChanged: (v) => update("guestControls", v),
                ),
                _SwitchTile(
                  label: "Guest Queueing",
                  subtitle: "Allow guests to add songs",
                  value: settings["guestQueueing"] ?? true,
                  onChanged: (v) => update("guestQueueing", v),
                ),
                _SwitchTile(
                  label: "Voting to Skip",
                  subtitle: "Enable vote-to-skip system",
                  value: settings["voteSkip"] ?? true,
                  onChanged: (v) => update("voteSkip", v),
                ),

                const SizedBox(height: 32),

                // ---- THEME ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "THEME",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      "Current: #${themeIndex + 1}",
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _themes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final isSelected = themeIndex == index;
                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(partyStateProvider.notifier)
                              .changeTheme(widget.party['id']);
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: _themes[index],
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  FontAwesomeIcons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showQRCode() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Scan to Join",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: "syncmusic://join/${widget.party['id']}",
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Close"),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _leaveParty() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "Leave Party?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "You can leave now and rejoin later with an invite. The party will be waiting 🎶",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("Leave Party"),
          ),
        ],
      ),
    );
  }

  void _endParty() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("End Party?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This will kick all members and close the party. Are you sure?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(partyStateProvider.notifier)
                  .endParty(widget.party["id"]);
            },
            child: const Text("End Party"),
          ),
        ],
      ),
    );
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
            final members = ref.watch(
              partyStateProvider.select((s) => s.members),
            );
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
                                          FontAwesomeIcons.circleMinus,
                                          color: Colors.redAccent,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          Navigator.pop(context);
                                          ref
                                              .read(partyStateProvider.notifier)
                                              .kickUser(
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
    ref
        .read(partyStateProvider.notifier)
        .sendReaction(widget.party["id"], emoji);
    _reactionStreamCtrl.add(emoji); // Local feedback immediate
  }

  void _addToLocalPlaylistDialog(yt.Video video) {
    final song = Song(
      id: video.id.value,
      title: video.title,
      url: video.url,
      thumbnail: video.thumbnails.lowResUrl,
      artist: video.author,
      duration: video.duration.toString(),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Handled by sheet
      isScrollControlled: true,
      builder: (context) => AddToPlaylistSheet(song: song),
    );
  }

  void _showMyPlaylistsImport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Handled by sheet
      isScrollControlled: true,
      builder: (context) => PlaylistImportSheet(
        partyId: widget.party["id"],
        username: widget.username,
      ),
    );
  }

  // ---- BUILD HELPERS ----
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- SEARCH RESULTS (TOP) ----
          if (searchCtrl.text.isNotEmpty && !isPlaylistDetected)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: searchResults.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        "No videos found",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: searchResults.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      itemBuilder: (_, i) {
                        final video = searchResults[i];
                        return InkWell(
                          onTap: () => _addVideo(video),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    video.thumbnails.lowResUrl,
                                    width: 34,
                                    height: 34,
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
                                IconButton(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.playlist_add,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () =>
                                      _addToLocalPlaylistDialog(video),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

          // ---- ACTION CHIPS ----
          Wrap(
            spacing: 8,
            children: [
              if (isPlaylistDetected)
                _ActionChip(
                  icon: FontAwesomeIcons.fileImport,
                  label: "Import playlist",
                  color: const Color(0xFF6C63FF),
                  onTap: _importPlaylist,
                ),
              _ActionChip(
                icon: FontAwesomeIcons.compactDisc,
                label: "My playlists",
                onTap: _showMyPlaylistsImport,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ---- SEARCH FIELD (BOTTOM) ----
          TextField(
            controller: searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Search YouTube or paste playlist link",
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              prefixIcon: Icon(
                FontAwesomeIcons.magnifyingGlass,
                size: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
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
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomNavItem(
    int index,
    IconData icon,
    String label, {
    bool hasBadge = false,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isSelected
        ? Theme.of(context).primaryColor
        : Colors.white.withValues(alpha: 0.4);

    return InkWell(
      onTap: () => _onItemTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 20),
                if (hasBadge && _unreadMessages > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _unreadMessages > 9 ? "9+" : "$_unreadMessages",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Top-level selects for Layout
    final themeIndex = ref.watch(
      partyStateProvider.select((s) => s.themeIndex),
    );
    final isDisconnected = ref.watch(
      partyStateProvider.select((s) => s.isDisconnected),
    );
    final partySize = ref.watch(partyStateProvider.select((s) => s.partySize));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));

    // Unread messages logic (Chat is now index 2)
    ref.listen(partyStateProvider.select((s) => s.messages.length), (
      prev,
      next,
    ) {
      if (_selectedIndex != 2) {
        final diff = next - (prev ?? 0);
        if (diff > 0) {
          setState(() {
            _unreadMessages += diff;
          });
        }
      }
    });

    // Listen for Party Ended State
    ref.listen(partyProvider.select((s) => s.isPartyEnded), (prev, ended) {
      if (ended) {
        if (mounted) {
          setState(() => _canPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final message = ref.read(partyProvider).endMessage;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => PartyEndedScreen(
                    message: message ?? "The host has ended the party.",
                  ),
                ),
              );
            }
          });
        }
      }
    });

    // Listen for Kicked State
    ref.listen(partyProvider.select((s) => s.isKicked), (prev, kicked) {
      if (kicked) {
        if (mounted) {
          setState(() => _canPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PartyKickedScreen()),
              );
            }
          });
        }
      }
    });

    // Force exit if global party state clears (e.g. Party Ended)
    ref.listen(partyProvider, (prev, next) {
      if (prev?.partyId != null && next.partyId == null) {
        if (mounted) {
          setState(() => _canPop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
          });
        }
      }
    });

    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await showExitConfirmationDialog(context, isHost);
        if (shouldLeave == true) {
          if (mounted) {
            setState(() => _canPop = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).pop();
            });
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset:
            true, // Allows content to move up for keyboard
        body: FloatingEmojis(
          reactionStream: _reactionStreamCtrl.stream,
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(gradient: _themes[themeIndex]),
              child: SafeArea(
                child: Column(
                  children: [
                    // ---- HEADER ----
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Reconnecting...",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
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
                                    Icon(
                                      FontAwesomeIcons.copy,
                                      size: 14,
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: _showMembersList,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        FontAwesomeIcons.users,
                                        size: 12,
                                        color: Theme.of(context).primaryColor,
                                      ),
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
                              _HeaderIconButton(
                                icon: FontAwesomeIcons.shareFromSquare,
                                onTap: _shareParty,
                              ),
                              const SizedBox(width: 8),
                              if (isHost) ...[
                                _HeaderIconButton(
                                  icon: FontAwesomeIcons.gear,
                                  onTap: _showSettings,
                                ),
                                const SizedBox(width: 8),
                                _HeaderIconButton(
                                  icon: FontAwesomeIcons.qrcode,
                                  onTap: _showQRCode,
                                ),
                                const SizedBox(width: 8),
                                _HeaderIconButton(
                                  icon: FontAwesomeIcons.powerOff,
                                  onTap: _endParty,
                                  color: Colors.redAccent,
                                ),
                              ] else ...[
                                _HeaderIconButton(
                                  icon: FontAwesomeIcons.qrcode,
                                  onTap: _showQRCode,
                                ),
                                const SizedBox(width: 8),
                                _HeaderIconButton(
                                  icon: FontAwesomeIcons.rightFromBracket,
                                  onTap: _leaveParty,
                                  color: Colors.redAccent,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ---- PLAYER & CONTROLS ----
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: PartyPlayer(
                        key: _playerKey,
                        partyId: widget.party['id'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildReactions(),
                    const SizedBox(height: 12),

                    // ---- TAB CONTENT ----
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          // 1. QUEUE
                          _KeepAliveWrapper(
                            child: Column(
                              children: [
                                Expanded(
                                  child: PartyQueue(
                                    partyId: widget.party['id'],
                                  ),
                                ),
                                _buildSearchBar(),
                              ],
                            ),
                          ),

                          // 2. LYRICS
                          const _KeepAliveWrapper(child: PartyLyrics()),

                          // 3. CHAT
                          _KeepAliveWrapper(
                            child: PartyChat(
                              partyId: widget.party['id'],
                              username: widget.username,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---- CUSTOM BOTTOM NAVIGATION ----
                    if (!isKeyboardOpen)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildBottomNavItem(
                              0,
                              FontAwesomeIcons.list,
                              "Queue",
                            ),
                            _buildBottomNavItem(
                              1,
                              FontAwesomeIcons.music,
                              "Lyrics",
                            ),
                            _buildBottomNavItem(
                              2,
                              FontAwesomeIcons.solidComment,
                              "Chat",
                              hasBadge: true,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
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

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
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
  final Color? color;

  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: color ?? Colors.white),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PresetCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).primaryColor,
            activeTrackColor: Theme.of(
              context,
            ).primaryColor.withValues(alpha: 0.3),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.grey.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withValues(
            alpha: color == null ? 0.08 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
