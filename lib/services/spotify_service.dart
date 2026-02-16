import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:spotify/spotify.dart' as sp;
import 'package:oauth2/oauth2.dart' as oauth2;

class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal();

  final _storage = const FlutterSecureStorage();
  sp.SpotifyApi? _spotify;
  oauth2.Client? _client;

  String get _clientId => dotenv.get('spotify_client_id');
  String get _clientSecret => dotenv.get('spotify_client_secret');
  String get _redirectUri => 'syncmusic://callback';

  final _authEndpoint = Uri.parse('https://accounts.spotify.com/authorize');
  final _tokenEndpoint = Uri.parse('https://accounts.spotify.com/api/token');

  Future<bool> isLoggedIn() async {
    if (_spotify != null && _client != null) {
      try {
        // Optional: A very lightweight check to see if the client is still valid
        // But for performance, we usually rely on the cached client.
        // If it fails later, the API calls will handle it.
        return true;
      } catch (_) {
        return false;
      }
    }

    final credentialsJson = await _storage.read(key: 'spotify_credentials');
    if (credentialsJson == null) return false;

    try {
      final credentials = oauth2.Credentials.fromJson(credentialsJson);

      _client = oauth2.Client(
        credentials,
        identifier: _clientId,
        secret: _clientSecret,
        onCredentialsRefreshed: (newCredentials) async {
          debugPrint("Spotify: Token refreshed successfully.");
          await _storage.write(
            key: 'spotify_credentials',
            value: newCredentials.toJson(),
          );
        },
      );

      _spotify = sp.SpotifyApi.fromClient(_client!);

      // Verification call to ensure the session is actually valid
      await _spotify!.me.get();
      return true;
    } catch (e) {
      debugPrint("Spotify Auth Error: $e");
      
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains("unexpected character") ||
          errorStr.contains("403") ||
          errorStr.contains("invalid_grant") ||
          errorStr.contains("developer.spotify.com/dashboard")) {
        debugPrint("Spotify: Session invalidated or whitelisting issue.");
        await logout();
      }
      return false;
    }
  }

  Future<bool> login() async {
    try {
      // Clear any old state before new login to ensure fresh start
      await logout();

      final grant = oauth2.AuthorizationCodeGrant(
        _clientId,
        _authEndpoint,
        _tokenEndpoint,
        secret: _clientSecret,
      );

      final authUri = grant.getAuthorizationUrl(
        Uri.parse(_redirectUri),
        scopes: [
          'user-read-private',
          'user-read-email',
          'user-library-read',
          'playlist-read-private',
          'playlist-read-collaborative',
        ],
      );

      final result = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: 'syncmusic',
      );

      final responseUri = Uri.parse(result);
      _client = await grant.handleAuthorizationResponse(
        responseUri.queryParameters,
      );

      _spotify = sp.SpotifyApi.fromClient(_client!);
      await _storage.write(
        key: 'spotify_credentials',
        value: _client!.credentials.toJson(),
      );

      return true;
    } catch (e) {
      debugPrint("Spotify Login Flow Error: $e");
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'spotify_credentials');
    _client?.close();
    _client = null;
    _spotify = null;
  }

  Future<List<sp.Track>> getLikedSongs() async {
    try {
      final ok = await isLoggedIn();
      if (!ok || _spotify == null) return [];

      final pages = await _spotify!.tracks.me.saved.getPage(20);
      return pages.items?.map((e) => e.track!).toList() ?? [];
    } catch (e) {
      await _handleApiError("Liked Songs", e);
      return [];
    }
  }

  Future<List<sp.PlaylistSimple>> getUserPlaylists() async {
    try {
      final ok = await isLoggedIn();
      if (!ok || _spotify == null) return [];

      final pages = await _spotify!.playlists.me.getPage(20);
      return pages.items?.toList() ?? [];
    } catch (e) {
      await _handleApiError("Playlists", e);
      return [];
    }
  }

  Future<List<sp.Track>> getPlaylistTracks(String playlistId) async {
    try {
      final ok = await isLoggedIn();
      if (!ok || _spotify == null) return [];

      final tracks = await _spotify!.playlists
          .getPlaylistTracks(playlistId)
          .all(50);
      return tracks.map((e) => e.track!).toList();
    } catch (e) {
      await _handleApiError("Playlist Tracks", e);
      return [];
    }
  }

  Future<List<sp.Track>> searchTracks(String query) async {
    try {
      final ok = await isLoggedIn();
      if (!ok || _spotify == null || query.isEmpty) return [];

      final search = await _spotify!.search
          .get(query, types: [sp.SearchType.track])
          .getPage(20);
      if (search.isEmpty) return [];

      for (var page in search) {
        if (page is sp.Page<sp.Track>) {
          return page.items?.toList() ?? [];
        }
      }
      return [];
    } catch (e) {
      await _handleApiError("Search", e);
      return [];
    }
  }

  Future<void> _handleApiError(String context, dynamic e) async {
    debugPrint("Spotify $context Error: $e");
    final errorStr = e.toString().toLowerCase();
    
    if (errorStr.contains("401") || errorStr.contains("403") || errorStr.contains("unexpected character")) {
      debugPrint("Spotify: API error suggests session is invalid or user lacks permission.");
      if (errorStr.contains("unexpected character") || errorStr.contains("developer.spotify.com")) {
         debugPrint("CRITICAL: Ensure the user email is whitelisted in Spotify Dev Dashboard -> Users and Roles.");
      }
      await logout();
    }
  }
}
