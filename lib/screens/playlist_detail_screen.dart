import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:sync_music/providers/playlist_provider.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:sync_music/widgets/custom_snackbar.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}


class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  void _addSongsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SearchAndAddSheet(
        onAdd: (video) {
          final song = Song(
            id: video.id.value,
            title: video.title,
            url: video.url,
            thumbnail: video.thumbnails.lowResUrl,
            artist: video.author,
            duration: video.duration.toString(),
          );
          ref
              .read(playlistProvider.notifier)
              .addSongToPlaylist(widget.playlistId, song);
          Navigator.pop(context);
          CustomSnackbar.show(context, "Added '${video.title}' to playlist");
        },
      ),
    );
  }

  void _renamePlaylist(Playlist playlist) {
    final TextEditingController controller = TextEditingController(
      text: playlist.name,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          "Rename Playlist",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "New Name",
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.deepPurpleAccent),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(playlistProvider.notifier)
                    .renamePlaylist(playlist.id, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text(
              "Save",
              style: TextStyle(color: Colors.deepPurpleAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistProvider);
    // Find the playlist
    final playlist = playlists.firstWhere(
      (p) => p.id == widget.playlistId,
      orElse: () => Playlist(id: "err", name: "Error", songs: []),
    );

    if (playlist.id == "err") {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            "Playlist not found",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(playlist.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _renamePlaylist(playlist),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSongsDialog,
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.5,
            colors: [Color(0xFF1A1F35), Colors.black],
          ),
        ),
        child: playlist.songs.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FontAwesomeIcons.music,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Playlist is empty",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: playlist.songs.length,
                onReorder: (oldIndex, newIndex) {
                  ref
                      .read(playlistProvider.notifier)
                      .reorderSong(playlist.id, oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final song = playlist.songs[index];
                  return Dismissible(
                    key: Key(song.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.redAccent,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      ref
                          .read(playlistProvider.notifier)
                          .removeSongFromPlaylist(playlist.id, song.id);
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          song.thumbnail,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey,
                            child: const Icon(Icons.music_note),
                          ),
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        song.artist,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () {
                              ref
                                  .read(playlistProvider.notifier)
                                  .removeSongFromPlaylist(playlist.id, song.id);
                            },
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.drag_handle,
                            color: Colors.white24,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SearchAndAddSheet extends StatefulWidget {
  final Function(yt.Video) onAdd;
  const _SearchAndAddSheet({required this.onAdd});

  @override
  State<_SearchAndAddSheet> createState() => _SearchAndAddSheetState();
}

class _SearchAndAddSheetState extends State<_SearchAndAddSheet> {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController _searchCtrl = TextEditingController();
  List<yt.Video> _results = [];
  bool _loading = false;
  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.isEmpty) {
        setState(() => _results = []);
        return;
      }
      setState(() => _loading = true);
      try {
        final results = await _ytService.searchVideos(query);
        if (mounted) {
          setState(() {
            _results = results;
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    _ytService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search YouTube...",
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final video = _results[index];
                      return ListTile(
                        leading: Image.network(
                          video.thumbnails.lowResUrl,
                          width: 50,
                          fit: BoxFit.cover,
                        ),
                        title: Text(
                          video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          video.author,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.deepPurpleAccent,
                          ),
                          onPressed: () => widget.onAdd(video),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
