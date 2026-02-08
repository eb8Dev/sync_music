import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/widgets/neon_empty.dart';
import 'package:sync_music/widgets/neon_loader.dart';
import 'package:sync_music/widgets/party_controls.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class PartyPlayer extends ConsumerStatefulWidget {
  final String partyId;
  final bool isFullScreen;
  final bool enableControlsOverlay;

  const PartyPlayer({
    super.key,
    required this.partyId,
    this.isFullScreen = false,
    this.enableControlsOverlay = true,
  });

  @override
  ConsumerState<PartyPlayer> createState() => PartyPlayerState();
}

class PartyPlayerState extends ConsumerState<PartyPlayer> {
  YoutubePlayerController? _controller;
  int? _lastEndedIndex;
  
  bool _showControls = true;
  Timer? _hideTimer;

  Duration? get currentPosition => _controller?.value.position;

  @override
  void initState() {
    super.initState();
    if (widget.enableControlsOverlay) {
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _hideTimer?.cancel();
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

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) _startHideTimer();
  }

  void _resetControls() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Select specific properties to minimize rebuilds
    final queue = ref.watch(partyStateProvider.select((s) => s.queue));
    final currentIndex = ref.watch(
      partyStateProvider.select((s) => s.currentIndex),
    );
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
      final emptyWidget = NeonEmptyState(isEndOfQueue: isEndOfQueue);

      if (widget.isFullScreen) {
        return Container(color: Colors.black, child: Center(child: emptyWidget));
      }

      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildGlassContainer(child: emptyWidget),
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
        return const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(child: Text("Invalid Video")),
        );
      }
    }

    // Imperative Sync Logic
    ref.listen(partyStateProvider, (prev, next) {
      if (_controller == null) return;
      
      // 1. Play/Pause state change
      if (!next.isPlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      } else if (next.isPlaying && !_controller!.value.isPlaying) {
        _controller!.play();
      }

      // 2. Position Sync (Only if playing and startedAt is provided)
      if (next.isPlaying && next.startedAt != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final targetPos = (now - next.startedAt!) ~/ 1000;
        final currentPos = _controller!.value.position.inSeconds;

        // Threshold-based seek
        // We only seek if:
        // - This is a "fresh" play (prev wasn't playing or was different index)
        // - OR the drift is significant (> 3s)
        final bool isNewPlay = prev == null || !prev.isPlaying || prev.currentIndex != next.currentIndex;
        final int threshold = isNewPlay ? 1 : 3;

        if ((targetPos - currentPos).abs() > threshold && targetPos >= 0) {
          debugPrint("Syncing playback: target=$targetPos, current=$currentPos");
          _controller!.seekTo(Duration(seconds: targetPos));
        }
      }
    });

    final playerWidget = YoutubePlayer(
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
          final now = DateTime.now().millisecondsSinceEpoch;
          if (startedAt != null) {
            final startSeconds = (now - startedAt) ~/ 1000;
            if (startSeconds > 0) {
              _controller!.seekTo(Duration(seconds: startSeconds));
            }
          }
          _controller!.play();
        }
      },
    );

    if (widget.isFullScreen) {
      // If fullscreen and controls enabled, use the overlay logic.
      // If controls disabled, just return playerWidget.
      if (!widget.enableControlsOverlay) {
        return playerWidget;
      }
       // Fallthrough to overlay logic
    } else {
      // If not fullscreen
      if (!widget.enableControlsOverlay) {
         return AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildGlassContainer(
              child: _controller == null
                  ? const NeonLoader()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: playerWidget,
                    ),
            ),
         );
      }
    }

    // Overlay Logic (Shared for Fullscreen & Standard if enabled)
    // We reuse the _buildGlassContainer wrapping only if NOT fullscreen
    Widget content = RepaintBoundary(
      child: _controller == null
          ? const NeonLoader()
          : MouseRegion(
              onEnter: (_) => _resetControls(),
              onHover: (_) => _resetControls(),
              child: GestureDetector(
                onTap: _toggleControls,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                     ClipRRect(
                      borderRadius: BorderRadius.circular(widget.isFullScreen ? 0 : 20),
                      child: playerWidget,
                    ),
                    
                    // Controls Overlay
                    AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                              ],
                              stops: const [0.6, 1.0],
                            ),
                          ),
                          child: Listener(
                            onPointerDown: (_) => _resetControls(),
                            child: Stack(
                              children: [
                                // Center Media Controls
                                Center(
                                  child: PartyControls(
                                    partyId: widget.partyId,
                                    enableDecoration: false,
                                  ),
                                ),
                                
                                // Bottom Progress Bar
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: _VideoProgressBar(
                                    controller: _controller!,
                                    isHost: isHost,
                                    onSeek: (seconds) {
                                      ref
                                          .read(partyStateProvider.notifier)
                                          .seek(widget.partyId, seconds);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );

      if (widget.isFullScreen) return content;

      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildGlassContainer(child: content),
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
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(24),
                // border: Border.all(
                //   color: Theme.of(context).colorScheme.primary.withValues(alpha:0.25),
                // ),
                boxShadow: [
                  BoxShadow(
                    color:
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35),
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

class _VideoProgressBar extends StatefulWidget {
  final YoutubePlayerController controller;
  final bool isHost;
  final Function(int) onSeek;

  const _VideoProgressBar({
    required this.controller,
    required this.isHost,
    required this.onSeek,
  });

  @override
  State<_VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<_VideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inHours > 0 ? '${twoDigits(duration.inHours)}:' : ''}$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: ValueListenableBuilder<YoutubePlayerValue>(
        valueListenable: widget.controller,
        builder: (context, value, child) {
          final duration = value.metaData.duration;
          final position = value.position;
          final totalSeconds = duration.inSeconds.toDouble();
          final currentSeconds = position.inSeconds.toDouble();
          
          // If dragging, show drag value, else show actual position
          final displayValue = _isDragging ? _dragValue : currentSeconds;
          // Clamp to ensure valid range
          final clampedValue = displayValue.clamp(0.0, totalSeconds > 0 ? totalSeconds : 0.0);
          final max = totalSeconds > 0 ? totalSeconds : 1.0;

          return Row(
            children: [
              Text(
                _formatDuration(Duration(seconds: clampedValue.toInt())),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 20, // Constrain height for slider
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: widget.isHost 
                          ? const RoundSliderThumbShape(enabledThumbRadius: 6) 
                          : const RoundSliderThumbShape(enabledThumbRadius: 0), // Hide thumb if guest
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Theme.of(context).primaryColor,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      min: 0.0,
                      max: max,
                      value: clampedValue,
                      onChanged: widget.isHost
                          ? (newValue) {
                              setState(() {
                                _isDragging = true;
                                _dragValue = newValue;
                              });
                            }
                          : null, // Disable interaction for guests
                      onChangeEnd: widget.isHost
                          ? (newValue) {
                              setState(() {
                                _isDragging = false;
                              });
                              widget.onSeek(newValue.toInt());
                            }
                          : null,
                    ),
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
