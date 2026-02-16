import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:sync_music/providers/party_state_provider.dart';
import 'package:sync_music/services/youtube_service.dart';
import 'package:sync_music/widgets/add_to_playlist_sheet.dart';
import 'package:sync_music/widgets/playlist_import_sheet.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class PartySearchBar extends ConsumerStatefulWidget {
  final String partyId;
  final String username;

  const PartySearchBar({
    super.key,
    required this.partyId,
    required this.username,
  });

  @override
  ConsumerState<PartySearchBar> createState() => _PartySearchBarState();
}

class _PartySearchBarState extends ConsumerState<PartySearchBar> {
  final YouTubeService _ytService = YouTubeService();
  final TextEditingController searchCtrl = TextEditingController();
  Timer? _debounce;
  List<yt.Video> searchResults = [];
  bool isSearching = false;
  bool isPlaylistDetected = false;

  @override
  void dispose() {
    searchCtrl.dispose();
    _debounce?.cancel();
    _ytService.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (isPlaylistDetected) {
      setState(() => isPlaylistDetected = false);
    }

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (query.isEmpty) {
        setState(() => searchResults = []);
        return;
      }

      if (query.contains("list=") && query.contains("youtube.com")) {
        setState(() {
          isPlaylistDetected = true;
          searchResults = [];
        });
        return;
      }

      final results = await _ytService.searchVideos(query);
      if (mounted) {
        setState(() => searchResults = results);
      }
    });
  }

  Future<void> _importPlaylist() async {
    final url = searchCtrl.text.trim();
    if (url.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      isSearching = true;
      isPlaylistDetected = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Importing top 15 songs from playlist...")),
    );

    try {
      final videos = await _ytService.getPlaylistVideos(url);

      int count = 0;
      for (var video in videos) {
        ref.read(partyStateProvider.notifier).addTrack(widget.partyId, {
          "url": video.url,
          "title": video.title,
          "addedBy": widget.username,
        });
        count++;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully added $count songs!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to import playlist.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
          searchCtrl.clear();
        });
      }
    }
  }

  void _addVideo(yt.Video video) {
    ref.read(partyStateProvider.notifier).addTrack(widget.partyId, {
      "url": video.url,
      "title": video.title,
      "addedBy": widget.username,
    });
    searchCtrl.clear();
    setState(() => searchResults = []);
    FocusScope.of(context).unfocus();
  }

  void _addToLocalPlaylistDialog(yt.Video video) {
    final song = Song(
      id: video.id.value,
      title: video.title,
      url: video.url,
      thumbnail: video.thumbnails.lowResUrl,
      artist: video.author,
      duration: video.duration.toString(),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddToPlaylistSheet(song: song),
    );
  }

  void _showMyPlaylistsImport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PlaylistImportSheet(
        partyId: widget.partyId,
        username: widget.username,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (searchCtrl.text.isNotEmpty && !isPlaylistDetected)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: searchResults.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        "No videos found",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: searchResults.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      itemBuilder: (_, i) {
                        final video = searchResults[i];
                        return InkWell(
                          onTap: () => _addVideo(video),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    video.thumbnails.lowResUrl,
                                    width: 34,
                                    height: 34,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    video.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.playlist_add,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () => _addToLocalPlaylistDialog(video),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (isPlaylistDetected)
                _ActionChip(
                  icon: FontAwesomeIcons.fileImport,
                  label: "Import playlist",
                  color: const Color(0xFF6C63FF),
                  onTap: _importPlaylist,
                ),
              _ActionChip(
                icon: FontAwesomeIcons.compactDisc,
                label: "My playlists",
                onTap: _showMyPlaylistsImport,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Search YouTube or paste playlist link",
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              prefixIcon: Icon(
                FontAwesomeIcons.magnifyingGlass,
                size: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withValues(
            alpha: color == null ? 0.08 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
