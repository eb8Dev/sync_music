import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/providers/playlist_provider.dart';
import 'package:sync_music/widgets/custom_snackbar.dart';

class PlaylistImportSheet extends ConsumerStatefulWidget {
  final String partyId;
  final String username;

  const PlaylistImportSheet({
    super.key,
    required this.partyId,
    required this.username,
  });

  @override
  ConsumerState<PlaylistImportSheet> createState() => _PlaylistImportSheetState();
}


class _PlaylistImportSheetState extends ConsumerState<PlaylistImportSheet> {
  Playlist? _selectedPlaylist;
  Set<String> _selectedSongIds = {};

  void _toggleSelection(String songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  void _selectAll() {
    if (_selectedPlaylist == null) return;
    setState(() {
      if (_selectedSongIds.length == _selectedPlaylist!.songs.length) {
        _selectedSongIds.clear();
      } else {
        _selectedSongIds = _selectedPlaylist!.songs.map((s) => s.id).toSet();
      }
    });
  }

  Future<void> _importSelected() async {
    if (_selectedPlaylist == null || _selectedSongIds.isEmpty) return;

    final songsToAdd = _selectedPlaylist!.songs
        .where((s) => _selectedSongIds.contains(s.id))
        .toList();

    Navigator.pop(context); // Close sheet

    // Optional: Filter out songs already in Queue to avoid duplicates?
    // User asked to check for duplicates.
    final currentQueue = ref.read(partyStateProvider).queue;
    int addedCount = 0;
    int skippedCount = 0;

    for (var song in songsToAdd) {
       // Simple duplicate check based on URL or ID if available in queue map
       final isDuplicate = currentQueue.any((track) {
         // Queue track usually has 'url' or 'id' (videoId)
         // Our Song model has 'url' and 'id'
         return track['url'] == song.url;
       });

       if (!isDuplicate) {
          ref.read(partyStateProvider.notifier).addTrack(widget.partyId, {
            "url": song.url,
            "title": song.title,
            "addedBy": widget.username,
          });
          addedCount++;
          // Small delay to prevent flooding
          await Future.delayed(const Duration(milliseconds: 50));
       } else {
         skippedCount++;
       }
    }

    if (mounted) {
       String msg = "Added $addedCount songs.";
       if (skippedCount > 0) {
         msg += " Skipped $skippedCount duplicates.";
       }
       CustomSnackbar.show(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistProvider);

    // If no playlist selected, show list of playlists
    if (_selectedPlaylist == null) {
      return SafeArea(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Import from Playlist",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (playlists.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      "No playlists found.",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.music_note, color: Colors.white),
                        ),
                        title: Text(
                          playlist.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          "${playlist.songs.length} songs",
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.white24,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedPlaylist = playlist;
                            // Default select all? Or none? Let's select all for convenience
                            _selectedSongIds = playlist.songs.map((s) => s.id).toSet();
                          });
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Show songs selection
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedPlaylist = null),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _selectedPlaylist!.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _selectAll,
                  child: Text(
                    _selectedSongIds.length == _selectedPlaylist!.songs.length
                        ? "Deselect All"
                        : "Select All",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _selectedPlaylist!.songs.length,
                itemBuilder: (context, index) {
                  final song = _selectedPlaylist!.songs[index];
                  final isSelected = _selectedSongIds.contains(song.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        song.thumbnail,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Colors.white10),
                      ),
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                      ),
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(song.id),
                      activeColor: Colors.deepPurpleAccent,
                    ),
                    onTap: () => _toggleSelection(song.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _selectedSongIds.isEmpty ? null : _importSelected,
                child: Text(
                  "Add ${_selectedSongIds.length} to Queue",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
