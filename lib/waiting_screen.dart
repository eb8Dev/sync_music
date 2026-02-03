import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/party_screen.dart';
import 'package:sync_music/movie_party_screen.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/user_provider.dart';
import 'package:sync_music/services/remote_config_service.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class WaitingScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> party;
  final String username;

  const WaitingScreen({super.key, required this.party, required this.username});

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen> {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();

  List<Video> searchResults = [];
  bool isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    // Initialize the party state provider with initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(partyStateProvider.notifier).init(widget.party);

      // If party is already playing, navigate to PartyScreen immediately
      if (widget.party["isPlaying"] == true) {
        final userState = ref.read(userProvider);
        final mode = widget.party["mode"] ?? "party";

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => mode == "movie"
                ? MoviePartyScreen(
                    party: widget.party,
                    username: "${userState.avatar} ${userState.username}",
                  )
                : PartyScreen(
                    party: widget.party,
                    username: "${userState.avatar} ${userState.username}",
                  ),
          ),
        );
      }
    });
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
                data: "syncmusic://join/${widget.party["id"]}",
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

  void _shareParty() {
    final serverUrl = RemoteConfigService().getServerUrl();
    final link = "$serverUrl/join/${widget.party["id"]}";
    SharePlus.instance.share(
      ShareParams(
        text:
            "Join my music party on Sync Music! use CODE: ${widget.party["id"]}.\nOr You can directly click on this $link to join.",
        subject: "Join Sync Music Party",
      ),
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _ytService.dispose();
    searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
        isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => isSearching = true);
      final results = await _ytService.searchVideos(query);
      if (mounted) {
        setState(() {
          searchResults = results;
          isSearching = false;
        });
      }
    });
  }

  Future<void> _addVideo(Video video) async {
    setState(() => isSearching = true);
    final isPlayable = await _ytService.isVideoPlayable(video.id.value);
    setState(() => isSearching = false);

    if (!mounted) return;

    if (!isPlayable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Cannot add this video (Age Restricted or Unavailable).",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check for duplicates
    final currentQueue = ref.read(partyStateProvider).queue;
    final isDuplicate = currentQueue.any((track) {
      final trackId = YoutubePlayer.convertUrlToId(track['url']);
      return trackId == video.id.value;
    });
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This video is already in the queue!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
      "url": video.url,
      "title": video.title,
      "addedBy": widget.username,
    });
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
  }

  void _startParty() {
    ref
        .read(partyStateProvider.notifier)
        .initiateCountdown(widget.party["id"], widget.username);
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.party["id"]));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Party Code Copied!")));
  }

  @override
  Widget build(BuildContext context) {
    final partyState = ref.watch(partyStateProvider);
    final bool isHost = ref.watch(partyProvider).isHost;
    final mode = widget.party["mode"] ?? "party";
    final isMovieMode = mode == "movie";

    // Listen for playback start to navigate to PartyScreen
    ref.listen(partyStateProvider, (previous, next) {
      if (next.isPlaying && (previous == null || !previous.isPlaying)) {
        final userState = ref.read(userProvider);
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => isMovieMode 
                ? MoviePartyScreen(
                    party: widget.party,
                    username: "${userState.avatar} ${userState.username}",
                  )
                : PartyScreen(
                    party: widget.party,
                    username: "${userState.avatar} ${userState.username}",
                  ),
          ),
        );
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.2),
                radius: 1.6,
                colors: [
                  Color(0xFF151922), // Surface
                  Color(0xFF0B0E14), // Background
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ---- CUSTOM HEADER ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "PARTY CODE",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha:0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _copyCode,
                            child: Row(
                              children: [
                                Text(
                                  widget.party["id"],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.copy_rounded, size: 16, color: Theme.of(context).primaryColor),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _HeaderActionButton(
                            icon: Icons.qr_code_rounded,
                            onTap: _showQRCode,
                          ),
                          const SizedBox(width: 12),
                          _HeaderActionButton(
                            icon: Icons.share_rounded,
                            onTap: _shareParty,
                            isPrimary: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ---- STATUS HERO ----
                Expanded(
                  child: partyState.queue.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).primaryColor.withValues(alpha:0.1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).primaryColor.withValues(alpha:0.2),
                                      blurRadius: 40,
                                      spreadRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isMovieMode ? Icons.movie_filter_rounded : (isHost ? Icons.headphones_rounded : Icons.headset_mic_rounded),
                                  size: 64,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const SizedBox(height: 32),
                              Text(
                                isHost ? "You are the Host" : "Waiting for Host",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isHost
                                    ? "Add ${isMovieMode ? 'videos' : 'songs'} to the queue to start."
                                    : "Sit tight! The party will start soon.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha:0.6),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: partyState.queue.length,
                          itemBuilder: (_, i) {
                            final track = partyState.queue[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GlassCard(
                                opacity: 0.05,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha:0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          "${i + 1}",
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              track["title"],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Added by ${track["addedBy"] ?? 'Unknown'}",
                                              style: TextStyle(
                                                color: Theme.of(context).primaryColor.withValues(alpha:0.8),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // ---- BOTTOM ACTION SHEET ----
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151922),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha:0.4),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: searchCtrl,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: isMovieMode ? "Add a movie to queue..." : "Add a song to queue...",
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha:0.4)),
                          prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha:0.4)),
                          suffixIcon: isSearching
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha:0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        ),
                      ),
                      
                      if (searchResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          margin: const EdgeInsets.only(top: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.05),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: searchResults.length,
                            separatorBuilder: (_, _) => Divider(height: 1, color: Colors.white.withValues(alpha:0.05)),
                            itemBuilder: (_, i) {
                              final video = searchResults[i];
                              return ListTile(
                                visualDensity: VisualDensity.compact,
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    video.thumbnails.lowResUrl,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                title: Text(
                                  video.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                                onTap: () => _addVideo(video),
                              );
                            },
                          ),
                        ),

                      if (isHost && partyState.queue.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _startParty,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 8,
                              shadowColor: Theme.of(context).primaryColor.withValues(alpha:0.4),
                            ),
                            child: const Text(
                              "START PARTY",
                              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (partyState.countdown != null)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Starting in",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 24,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(partyState.countdown),
                    tween: Tween(begin: 1.5, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Text(
                          "${partyState.countdown}",
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontSize: 120,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _HeaderActionButton({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isPrimary ? Theme.of(context).primaryColor : Colors.white.withValues(alpha:0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary ? Colors.transparent : Colors.white.withValues(alpha:0.1),
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isPrimary ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}