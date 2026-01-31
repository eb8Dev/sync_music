import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/widgets/glass_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class PartyQueue extends ConsumerWidget {
  final String partyId;

  const PartyQueue({super.key, required this.partyId});

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

        return Padding(
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
                      ? theme.primaryColor.withOpacity(0.2) 
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: isCurrent 
                      ? Border.all(color: theme.primaryColor.withOpacity(0.5)) 
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
                          errorWidget: (context, url, error) => const Icon(Icons.music_note, color: Colors.white54, size: 20),
                        ),
                      )
                    : (isCurrent
                        ? Icon(
                            Icons.equalizer_rounded,
                            color: theme.primaryColor,
                            size: 20,
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
                    color: isCurrent ? theme.primaryColor.withOpacity(0.8) : Colors.white38,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

              // Trailing action
              trailing: isHost
                  ? IconButton(
                      splashRadius: 20,
                      icon: Icon(
                        Icons.remove_circle_outline_rounded,
                        color: Colors.white.withOpacity(0.3),
                        size: 20,
                      ),
                      onPressed: () => notifier.removeTrack(partyId, track["id"]),
                    )
                  : null,

              onTap: isHost ? () => notifier.changeTrack(partyId, i) : null,
            ),
          ),
        );
      },
    );
  }
}
