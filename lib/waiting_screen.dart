import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/party_screen.dart';
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
    });
  }

  void _showQRCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "Scan to Join",
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: widget.party["id"],
              version: QrVersions.auto,
              size: 250.0,
              backgroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _shareParty() {
    final serverUrl = RemoteConfigService().getServerUrl();
    final link = "$serverUrl/join/${widget.party["id"]}";
    SharePlus.instance.share(
      ShareParams(
        text: "Join my music party on Sync Music! Click here: $link",
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

  void _addVideo(Video video) {
    ref.read(partyStateProvider.notifier).addTrack(widget.party["id"], {
      "url": video.url,
      "title": video.title,
      "addedBy": widget.username,
    });
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Added '${video.title}' to queue"),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startParty() {
    ref.read(partyStateProvider.notifier).play(widget.party["id"]);
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

    // Listen for playback start to navigate to PartyScreen
    ref.listen(partyStateProvider, (previous, next) {
      if (next.isPlaying && (previous == null || !previous.isPlaying)) {
        final userState = ref.read(userProvider);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PartyScreen(
              party: widget.party,
              username: "${userState.avatar} ${userState.username}",
            ),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _copyCode,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("CODE: ${widget.party["id"]}"),
              const SizedBox(width: 8),
              const Icon(Icons.copy, size: 16),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, size: 20, color: Colors.white70),
            onPressed: _shareParty,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: IconButton(
              icon: const Icon(Icons.qr_code, size: 20, color: Colors.white70),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
              onPressed: _showQRCode,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121212), Color(0xFF1E1E1E)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassCard(
                opacity: 0.05,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        isHost ? Icons.local_activity : Icons.headset,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        isHost ? "YOU ARE HOST" : "WAITING FOR HOST TO START",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Simplified logs for now, using the messages from provider if they are system type
            if (partyState.messages.any((m) => m['type'] == 'system'))
              Container(
                height: 100,
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  reverse: true,
                  children: partyState.messages
                      .where((m) => m['type'] == 'system')
                      .toList()
                      .reversed
                      .map(
                        (m) => Text(
                          m['text'] ?? "",
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

            const SizedBox(height: 12),
            Expanded(
              child: partyState.queue.isEmpty
                  ? Center(
                      child: Text(
                        "Queue is empty",
                        style: TextStyle(color: Colors.white.withOpacity(0.3)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: partyState.queue.length,
                      itemBuilder: (_, i) {
                        final track = partyState.queue[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            opacity: 0.05,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              dense: true,
                              leading: Text(
                                "${i + 1}",
                                style: const TextStyle(color: Colors.white54),
                              ),
                              title: Text(
                                track["title"],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                "By ${track["addedBy"] ?? 'Unknown'}",
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF121212),
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "Search YouTube songs...",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (_, i) {
                          final video = searchResults[i];
                          return ListTile(
                            leading: Image.network(
                              video.thumbnails.lowResUrl,
                              width: 40,
                              fit: BoxFit.cover,
                            ),
                            title: Text(
                              video.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () => _addVideo(video),
                          );
                        },
                      ),
                    ),
                  if (isHost) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("START PARTY"),
                        onPressed: _startParty,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
