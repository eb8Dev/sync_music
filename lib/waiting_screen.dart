import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sync_music/party_screen.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class WaitingScreen extends StatefulWidget {
  final IO.Socket socket;
  final Map<String, dynamic> party;
  final String username;

  const WaitingScreen({
    super.key,
    required this.socket,
    required this.party,
    required this.username,
  });

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  
  List<dynamic> queue = [];
  List<Video> searchResults = [];
  bool isSearching = false;
  Timer? _debounce;

  // Listeners
  late dynamic _queueListener;
  late dynamic _playbackListener;
  late dynamic _errorListener;

  @override
  void initState() {
    super.initState();
    queue = List.from(widget.party["queue"] ?? []);

    // ---- Define Listeners ----
    _queueListener = (data) {
      if (!mounted) return;
      setState(() {
        queue = List.from(data);
      });
    };

    _playbackListener = (data) {
      if (!mounted) return;
      // Transition to PartyScreen
      final updatedParty = {
        ...widget.party,
        "queue": queue,
        "currentIndex": data["currentIndex"],
        "startedAt": data["startedAt"],
        "isPlaying": data["isPlaying"],
        "isHost": widget.party["isHost"],
      };

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PartyScreen(
            socket: widget.socket,
            party: updatedParty,
            username: widget.username,
          ),
        ),
      );
    };

    _errorListener = (msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
      Navigator.popUntil(context, (route) => route.isFirst);
    };

    // ---- Attach Listeners ----
    widget.socket.on("QUEUE_UPDATED", _queueListener);
    widget.socket.on("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.on("ERROR", _errorListener);

    // Initial check
    if (widget.party["isPlaying"] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Manually trigger nav if already playing
        _playbackListener(widget.party);
      });
    }
  }

  @override
  void dispose() {
    widget.socket.off("QUEUE_UPDATED", _queueListener);
    widget.socket.off("PLAYBACK_UPDATE", _playbackListener);
    widget.socket.off("ERROR", _errorListener);
    _ytService.dispose();
    searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ---- Search & Add ----
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
    widget.socket.emit("ADD_TRACK", {
      "partyId": widget.party["id"],
      "track": {
        "url": video.url, 
        "title": video.title, 
        "addedBy": widget.username
      },
    });
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
  }

  // ---- Start Party ----
  void _startParty() {
    widget.socket.emit("PLAY", {"partyId": widget.party["id"]});
  }

  // ---- QR ----
  void _showQr() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Scan to Join", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 200, height: 200,
          child: Center(
            child: QrImageView(
              data: widget.party["id"],
              backgroundColor: Colors.white,
              size: 200,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isHost = widget.party["isHost"] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text("CODE: ${widget.party["id"]}"),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code), onPressed: _showQr),
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
            
            // ---- Status ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassCard(
                opacity: 0.05,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(isHost ? Icons.local_activity : Icons.headset, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 16),
                      Text(
                        isHost ? "YOU ARE HOST" : "WAITING FOR HOST",
                        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            // ---- Queue ----
            Expanded(
              child: queue.isEmpty
                  ? Center(child: Text("Queue is empty", style: TextStyle(color: Colors.white.withOpacity(0.3))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: queue.length,
                      itemBuilder: (_, i) {
                        final track = queue[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            opacity: 0.05,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              dense: true,
                              leading: Text("${i + 1}", style: const TextStyle(color: Colors.white54)),
                              title: Text(track["title"], maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text("By ${track["addedBy"] ?? 'Unknown'}", style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 10)),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // ---- Search Bar ----
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
                          ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))) 
                          : null,
                    ),
                  ),
                  
                  // Search Results List
                  if (searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (_, i) {
                          final video = searchResults[i];
                          return ListTile(
                            leading: Image.network(video.thumbnails.lowResUrl, width: 40, fit: BoxFit.cover),
                            title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
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
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
