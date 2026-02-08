import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricsService {
  // Switched to LrcLib.net (Open Source, reliable)
  static const String _searchUrl = 'https://lrclib.net/api/search';

  Future<String?> fetchLyrics(String videoTitle) async {
    try {
      // 1. Clean up title (Aggressive cleaning for Indian/Bollywood titles)
      String cleanTitle = _cleanTitle(videoTitle);

      // 2. Strategy A: Search with the full cleaned title
      var lyrics = await _search(cleanTitle);
      if (lyrics != null) return lyrics;

      // 3. Strategy B: If title has " - ", try searching just the Song Name (part 2)
      if (cleanTitle.contains(" - ")) {
          final parts = cleanTitle.split(" - ");
          if (parts.length >= 2) {
             lyrics = await _search(parts[0].trim());
             if (lyrics != null) return lyrics;
          }
      }

      return "No lyrics found for '$cleanTitle'.";
    } catch (e) {
      // Rethrow so the UI can show the Retry button
      throw e;
    }
  }

  Future<String?> _search(String query) async {
      final url = Uri.parse('$_searchUrl?q=${Uri.encodeComponent(query)}');
      
      int attempts = 0;
      while (attempts < 3) {
        try {
          final response = await http.get(url).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final List<dynamic> data = json.decode(response.body);
            if (data.isEmpty) return null;

            final match = data.firstWhere(
              (item) => item['plainLyrics'] != null && (item['plainLyrics'] as String).isNotEmpty,
              orElse: () => null,
            );
            return match != null ? match['plainLyrics'] : null;
          } else {
             // If server error (5xx), maybe retry. If 4xx, probably don't retry.
             if (response.statusCode >= 500) {
                throw Exception("Server Error: ${response.statusCode}");
             }
             // For 4xx errors, just return null (not found/bad request)
             return null;
          }
        } catch (e) {
          attempts++;
          if (attempts >= 3) rethrow;
          // Exponential backoff: 1s, 2s
          await Future.delayed(Duration(seconds: attempts)); 
        }
      }
      return null;
  }

  String _cleanTitle(String title) {
    // 1. Remove bracketed content (...) and [...]
    var cleaned = title
        .replaceAll(RegExp(r"\(.*?\)|\[.*?\]"), "")
        .replaceAll(RegExp(r"\|.*"), ""); // Remove pipe and after

    // 2. Remove specific keywords (case insensitive)
    final junkPattern = RegExp(
      r"\b(official video|official music video|full video|full song|lyrical video|with lyrics|video song|lyrics|ft\.|feat\.|hq|4k|hd)\b",
      caseSensitive: false,
    );
    
    cleaned = cleaned.replaceAll(junkPattern, "");

    return cleaned.trim();
  }
}