import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/widgets/neon_empty.dart';
import 'package:sync_music/widgets/neon_loader.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class PartyPlayer extends ConsumerStatefulWidget {
  final String partyId;

  const PartyPlayer({super.key, required this.partyId});

  @override
  ConsumerState<PartyPlayer> createState() => _PartyPlayerState();
}

class _PartyPlayerState extends ConsumerState<PartyPlayer> {
  YoutubePlayerController? _controller;
  int? _lastEndedIndex;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _initController(String url) {
    final videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId == null) return;

    _controller?.dispose();
    _controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        enableCaption: false,
        hideControls: true,
        mute: false,
        loop: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Select specific properties to minimize rebuilds
    final queue = ref.watch(partyStateProvider.select((s) => s.queue));
    final currentIndex = ref.watch(partyStateProvider.select((s) => s.currentIndex));
    final isPlaying = ref.watch(partyStateProvider.select((s) => s.isPlaying));
    final startedAt = ref.watch(partyStateProvider.select((s) => s.startedAt));
    final isHost = ref.watch(partyProvider.select((s) => s.isHost));

    final bool isEndOfQueue = currentIndex >= queue.length && queue.isNotEmpty;
    final bool isEmptyQueue = queue.isEmpty;
    final bool showPlayer = !isEmptyQueue && !isEndOfQueue;

    if (!showPlayer) {
      // If we are showing empty state, dispose controller to free resources
      if (_controller != null) {
        _controller!.dispose();
        _controller = null;
      }
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildGlassContainer(
           child: NeonEmptyState(isEndOfQueue: isEndOfQueue),
        ),
      );
    }

    final currentTrack = queue[currentIndex];
    final url = currentTrack['url'];
    final videoId = YoutubePlayer.convertUrlToId(url);

    // If controller is null or playing different video, re-init
    if (_controller == null || _controller!.initialVideoId != videoId) {
      if (videoId != null) {
        _initController(url);
      } else {
         return AspectRatio(aspectRatio: 16/9, child: const Center(child: Text("Invalid Video")));
      }
    }

    // Imperative Sync Logic
    // We do this in build or listener. 
    // Doing it here ensures if parent rebuilds we re-check state.
    // However, calling seekTo/play repeatedly in build is bad.
    // We should use a side-effect listener or check if state actually diverged.
    // For this refactor, we rely on the controller's internal state vs provided state.
    
    // Actually, listening to state changes for imperative logic (seek/play) is better done via ref.listen
    ref.listen(partyStateProvider, (prev, next) {
      if (_controller == null) return;
      if (!next.isPlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      } else if (next.isPlaying && !_controller!.value.isPlaying) {
        _controller!.play();
      }
      
      // Sync check (simple version)
      if (next.isPlaying && next.startedAt != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final targetPos = (now - next.startedAt!) ~/ 1000;
          final currentPos = _controller!.value.position.inSeconds;
          
          if ((targetPos - currentPos).abs() > 2) {
             _controller!.seekTo(Duration(seconds: targetPos));
          }
      }
    });

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _buildGlassContainer(
        child: _controller == null
            ? const NeonLoader()
            : ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: YoutubePlayer(
                  key: ValueKey(videoId), // Force rebuild if ID changes
                  controller: _controller!,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: Theme.of(context).colorScheme.primary,
                  onEnded: (_) {
                    if (isHost && _lastEndedIndex != currentIndex) {
                      _lastEndedIndex = currentIndex;
                      ref.read(partyStateProvider.notifier).endTrack(widget.partyId);
                    }
                  },
                  onReady: () {
                    // Initial sync on load
                    if (isPlaying) {
                      int startSeconds = 0;
                      final now = DateTime.now().millisecondsSinceEpoch;
                      if (startedAt != null && now > startedAt) {
                        startSeconds = (now - startedAt) ~/ 1000;
                      }
                      _controller!.seekTo(Duration(seconds: startSeconds));
                      _controller!.play();
                    }
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          // Background Glow Layer
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A0F1F), Color(0xFF120A2A)],
              ),
            ),
          ),
          // Glass Blur Layer
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(24),
                // border: Border.all(
                //   color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                // ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
