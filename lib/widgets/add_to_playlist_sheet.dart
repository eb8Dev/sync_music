import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:sync_music/providers/playlist_provider.dart';

import 'package:sync_music/widgets/custom_snackbar.dart';

class AddToPlaylistSheet extends ConsumerWidget {
  final Song song;
  final VoidCallback? onSuccess;

  const AddToPlaylistSheet({
    super.key,
    required this.song,
    this.onSuccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  song.thumbnail,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.white10,
                    child: const Icon(Icons.music_note, color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Add to Playlist",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (playlists.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    const Text(
                      "No playlists found.",
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // TODO: Navigate to create playlist or show dialog
                        Navigator.pop(context);
                      },
                      child: const Text("Create one in Settings"),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  // Check if song already exists in playlist
                  final bool exists = playlist.songs.any((s) => s.id == song.id);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: exists 
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : const Icon(Icons.music_note, color: Colors.white),
                    ),
                    title: Text(
                      playlist.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      "${playlist.songs.length} songs",
                      style: const TextStyle(color: Colors.white54),
                    ),
                    onTap: () {
                      if (exists) {
                        CustomSnackbar.show(
                          context,
                          "Already in ${playlist.name}",
                          isError: true,
                        );
                        return;
                      }
                      ref.read(playlistProvider.notifier).addSongToPlaylist(playlist.id, song);
                      Navigator.pop(context);
                      CustomSnackbar.show(context, "Added to ${playlist.name}");
                      onSuccess?.call();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
