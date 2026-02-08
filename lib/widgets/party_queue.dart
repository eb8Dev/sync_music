import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/widgets/add_to_playlist_sheet.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class PartyQueue extends ConsumerWidget {
  final String partyId;

  const PartyQueue({super.key, required this.partyId});

  void _showAddToPlaylist(BuildContext context, Map<String, dynamic> track) {
     // Convert track map to Song model
     final videoId = YoutubePlayer.convertUrlToId(track['url'] ?? "") ?? "";
     final song = Song(
       id: videoId, // Use videoId as ID for consistency
       title: track['title'] ?? "Unknown Title",
       url: track['url'] ?? "",
       thumbnail: "https://img.youtube.com/vi/$videoId/mqdefault.jpg",
       artist: track['addedBy'] ?? "Unknown", // Metadata might be missing, use addedBy or default
     );

     showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddToPlaylistSheet(song: song),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(partyStateProvider.select((s) => s.queue));
    final currentIndex = ref.watch(partyStateProvider.select((s) => s.currentIndex));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));
    
    // We also need access to the notifier, but we don't watch it.
    final notifier = ref.read(partyStateProvider.notifier);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: queue.length,
      itemBuilder: (context, i) {
        final track = queue[i];
        final isCurrent = i == currentIndex;
        final theme = Theme.of(context);
        
        final videoId = YoutubePlayer.convertUrlToId(track['url'] ?? "");
        final thumbnailUrl = videoId != null 
            ? "https://img.youtube.com/vi/$videoId/mqdefault.jpg" 
            : null;

        return RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              enableBlur: false, // PERFORMANCE FIX
              opacity: isCurrent ? 0.12 : 0.05,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
  
                // Leading: Thumbnail or Index
                leading: Container(
                  width: 50,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCurrent 
                        ? theme.primaryColor.withValues(alpha:0.2) 
                        : Colors.white.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: isCurrent 
                        ? Border.all(color: theme.primaryColor.withValues(alpha:0.5)) 
                        : null,
                  ),
                  child: thumbnailUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: thumbnailUrl,
                            width: 50,
                            height: 40,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.white10),
                            errorWidget: (context, url, error) => const Icon(FontAwesomeIcons.music, color: Colors.white54, size: 16),
                          ),
                        )
                      : (isCurrent
                          ? Icon(
                              FontAwesomeIcons.chartSimple,
                              color: theme.primaryColor,
                              size: 16,
                            )
                          : Text(
                              "${i + 1}",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            )),
                ),
  
                // Title
                title: Text(
                  track["title"],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: isCurrent ? Colors.white : Colors.white70,
                    letterSpacing: 0.3,
                  ),
                ),
  
                // Subtitle
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "Added by ${track["addedBy"] ?? 'Unknown'}",
                    style: TextStyle(
                      color: isCurrent ? theme.primaryColor.withValues(alpha:0.8) : Colors.white38,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
  
                // Trailing action
                trailing: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: Colors.white.withValues(alpha:0.3),
                    size: 20,
                  ),
                  color: const Color(0xFF1E1E1E),
                  onSelected: (value) {
                    if (value == 'add_to_playlist') {
                      _showAddToPlaylist(context, track);
                    } else if (value == 'remove') {
                      notifier.removeTrack(partyId, track["id"]);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'add_to_playlist',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text("Add to Playlist", style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    if (isHost)
                      const PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text("Remove", style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                  ],
                ),
  
                onTap: isHost ? () => notifier.changeTrack(partyId, i) : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
