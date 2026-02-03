import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<Video>> searchVideos(String query) async {
    try {
      // 1. Check if it's a direct URL or ID
      VideoId? videoId;
      try {
        videoId = VideoId(query);
      } catch (_) {
        // Not a valid ID/URL format
      }

      if (videoId != null) {
        final video = await _yt.videos.get(videoId);
        return [video];
      }

      // 2. Fallback to standard search
      final searchList = await _yt.search.search(query);
      return searchList.take(5).toList();
    } catch (e) {
      return [];
    }
  }

  Future<Video?> getVideoDetails(String url) async {
    try {
      return await _yt.videos.get(url);
    } catch (e) {
      return null;
    }
  }

  Future<List<Video>> getPlaylistVideos(String url) async {
    try {
      final playlistId = PlaylistId(url);
      final playlist = await _yt.playlists.getVideos(playlistId).take(15).toList();
      return playlist;
    } catch (e) {
      return [];
    }
  }

  Future<bool> isVideoPlayable(String videoId) async {
    try {
      // Try to get manifest. If it fails, it's likely restricted or unplayable.
      await _yt.videos.streamsClient.getManifest(videoId);      
      return true;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _yt.close();
  }
}
