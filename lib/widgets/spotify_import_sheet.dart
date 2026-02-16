import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:spotify/spotify.dart' as sp;
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/services/spotify_service.dart';
import 'package:sync_music/services/youtube_service.dart';

class SpotifyImportSheet extends ConsumerStatefulWidget {
  final String partyId;
  final String username;

  const SpotifyImportSheet({super.key, required this.partyId, required this.username});

  @override
  ConsumerState<SpotifyImportSheet> createState() => _SpotifyImportSheetState();
}

class _SpotifyImportSheetState extends ConsumerState<SpotifyImportSheet> {
  final SpotifyService _spotifyService = SpotifyService();
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController _searchCtrl = TextEditingController();
  
  bool _isLoading = true;
  List<sp.Track> _tracks = [];
  List<sp.PlaylistSimple> _playlists = [];
  String _view = 'liked'; // 'liked', 'playlists', 'playlist_detail', 'search'
  String? _selectedPlaylistName;
  Timer? _debounce;
  final Set<String> _importingIds = {};

  @override
  void initState() {
    super.initState();
    _loadLikedSongs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.isEmpty) {
      _loadLikedSongs();
      return;
    }

    setState(() {
      _isLoading = true;
      _view = 'search';
    });

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final results = await _spotifyService.searchTracks(query);
      if (mounted) {
        setState(() {
          _tracks = results;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _loadLikedSongs() async {
    setState(() {
      _isLoading = true;
      _view = 'liked';
      _searchCtrl.clear();
    });
    final tracks = await _spotifyService.getLikedSongs();
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _isLoading = true;
      _view = 'playlists';
      _searchCtrl.clear();
    });
    final playlists = await _spotifyService.getUserPlaylists();
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPlaylistTracks(sp.PlaylistSimple playlist) async {
    setState(() {
      _isLoading = true;
      _selectedPlaylistName = playlist.name;
      _view = 'playlist_detail';
    });
    final tracks = await _spotifyService.getPlaylistTracks(playlist.id!);
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _importTrack(sp.Track track) async {
    if (track.id == null || _importingIds.contains(track.id)) return;

    // Check for duplicates in current queue before processing
    final currentQueue = ref.read(partyStateProvider).queue;
    final isAlreadyInQueue = currentQueue.any((t) => t['title'] == track.name);
    if (isAlreadyInQueue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("'${track.name}' is already in the queue"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _importingIds.add(track.id!));
    
    final query = "${track.name} ${track.artists?.first.name ?? ''}";
    
    try {
      final ytResults = await _ytService.searchVideos(query);
      if (ytResults.isNotEmpty) {
        final bestMatch = ytResults.first;
        
        // Final duplicate check using URL
        final isDuplicateUrl = currentQueue.any((t) => t['url'] == bestMatch.url);
        if (isDuplicateUrl) {
           if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("'${track.name}' is already in the queue (matched via YouTube)"), backgroundColor: Colors.orange),
            );
          }
          return;
        }

        ref.read(partyStateProvider.notifier).addTrack(widget.partyId, {
          "url": bestMatch.url,
          "title": track.name,
          "addedBy": widget.username,
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Added '${track.name}'"), duration: const Duration(seconds: 1)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not find matching video on YouTube"), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      debugPrint("Conversion Error for '${track.name}': $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error importing '${track.name}'"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importingIds.remove(track.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                const Icon(FontAwesomeIcons.spotify, color: Color(0xFF1DB954), size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _view == 'playlists' ? "Your Playlists" : (_view == 'playlist_detail' ? _selectedPlaylistName ?? "Playlist" : (_view == 'search' ? "Search Results" : "Liked Songs")),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Text("Import to Party Queue", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search Spotify tracks...",
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              ),
            ),
          ),

          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Row(
              children: [
                _buildTabBtn("Liked", _view == 'liked' || (_view == 'search' && _searchCtrl.text.isEmpty), _loadLikedSongs),
                const SizedBox(width: 12),
                _buildTabBtn("Playlists", _view == 'playlists' || _view == 'playlist_detail', _loadPlaylists),
              ],
            ),
          ),
          
          const SizedBox(height: 12),

          // Content
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
              : (_view == 'playlists' ? _buildPlaylistGrid() : _buildTrackList()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1DB954) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildTrackList() {
    if (_tracks.isEmpty) return const Center(child: Text("No tracks found", style: TextStyle(color: Colors.white38)));
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isImporting = _importingIds.contains(track.id);

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              track.album?.images?.first.url ?? "",
              width: 48, height: 48, fit: BoxFit.cover,
              errorBuilder: (_,__,___) => Container(color: Colors.white10, child: const Icon(Icons.music_note, color: Colors.white24)),
            ),
          ),
          title: Text(track.name ?? "Unknown", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(track.artists?.map((e) => e.name).join(", ") ?? "Unknown Artist", style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: isImporting 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954)))
            : IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF1DB954)),
                onPressed: () => _importTrack(track),
              ),
        );
      },
    );
  }

  Widget _buildPlaylistGrid() {
    if (_playlists.isEmpty) return const Center(child: Text("No playlists found", style: TextStyle(color: Colors.white38)));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        return GestureDetector(
          onTap: () => _loadPlaylistTracks(playlist),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    playlist.images?.first.url ?? "",
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_,__,___) => Container(color: Colors.white10, child: const Icon(Icons.queue_music, color: Colors.white24, size: 48)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(playlist.name ?? "Untitled", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text("${playlist.tracksLink?.total ?? 0} Tracks", style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}
