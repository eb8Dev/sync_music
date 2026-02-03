import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/services/lyrics_service.dart';

class PartyLyrics extends ConsumerStatefulWidget {
  const PartyLyrics({super.key});

  @override
  ConsumerState<PartyLyrics> createState() => _PartyLyricsState();
}

class _PartyLyricsState extends ConsumerState<PartyLyrics>
    with AutomaticKeepAliveClientMixin {
  final LyricsService _lyricsService = LyricsService();
  String? _currentTitle;
  Future<String?>? _lyricsFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final queue = ref.watch(partyStateProvider.select((s) => s.queue));
    final currentIndex = ref.watch(partyStateProvider.select((s) => s.currentIndex));
    
    // Safety check
    if (queue.isEmpty || currentIndex >= queue.length) {
      return const Center(
        child: Text(
          "Play a song to see lyrics",
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final track = queue[currentIndex];
    final title = track['title'];

    // Update Future if track changed
    if (title != _currentTitle) {
      _currentTitle = title;
      _loadLyrics(title);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
           Text(
             title,
             style: const TextStyle(
               color: Colors.white,
               fontSize: 18,
               fontWeight: FontWeight.bold,
             ),
             textAlign: TextAlign.center,
             maxLines: 2,
             overflow: TextOverflow.ellipsis,
           ),
           const SizedBox(height: 4),
           Text(
             "Added by ${track['addedBy'] ?? 'Unknown'}",
             style: const TextStyle(color: Colors.white54, fontSize: 12),
           ),
           const SizedBox(height: 24),
           Expanded(
             child: FutureBuilder<String?>(
               future: _lyricsFuture,
               builder: (context, snapshot) {
                 if (snapshot.connectionState == ConnectionState.waiting) {
                   return const Center(child: CircularProgressIndicator());
                 }
                 if (snapshot.hasError) {
                   return Center(
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         const Icon(Icons.error_outline, color: Colors.white38, size: 48),
                         const SizedBox(height: 12),
                         Text(
                           "Could not load lyrics.\n${snapshot.error.toString().contains('Timeout') ? 'Connection timed out' : 'Network error'}", 
                           style: const TextStyle(color: Colors.white38),
                           textAlign: TextAlign.center,
                         ),
                         const SizedBox(height: 16),
                         ElevatedButton.icon(
                            onPressed: () => _loadLyrics(title),
                            icon: const Icon(Icons.refresh),
                            label: const Text("Retry"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha:0.1),
                              foregroundColor: Colors.white,
                            ),
                         ),
                       ],
                     ),
                   );
                 }
                 
                 final lyrics = snapshot.data ?? "No lyrics found.";
                 return SingleChildScrollView(
                   physics: const BouncingScrollPhysics(),
                   child: Text(
                     lyrics,
                     style: const TextStyle(
                       color: Colors.white,
                       fontSize: 16,
                       height: 1.6,
                       fontWeight: FontWeight.w500,
                     ),
                     textAlign: TextAlign.center,
                   ),
                 );
               },
             ),
           ),
        ],
      ),
    );
  }

  void _loadLyrics(String title) {
     setState(() {
         _lyricsFuture = _lyricsService.fetchLyrics(title);
     });
  }
}
