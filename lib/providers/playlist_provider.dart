import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_music/models/playlist_model.dart';
import 'package:uuid/uuid.dart';

class PlaylistNotifier extends Notifier<List<Playlist>> {
  static const _storageKey = 'user_playlists';

  @override
  List<Playlist> build() {
    _loadPlaylists();
    return [];
  }

  Future<void> _loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_storageKey);
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      state = jsonList.map((e) => Playlist.fromJson(e)).toList();
    } else {
      state = [];
    }
  }

  Future<void> _savePlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<void> createPlaylist(String name) async {
    final newPlaylist = Playlist(
      id: const Uuid().v4(),
      name: name,
      songs: [],
    );
    state = [...state, newPlaylist];
    await _savePlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _savePlaylists();
  }

  Future<void> renamePlaylist(String id, String newName) async {
    state = state.map((p) {
      if (p.id == id) {
        return p.copyWith(name: newName);
      }
      return p;
    }).toList();
    await _savePlaylists();
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    state = state.map((p) {
      if (p.id == playlistId) {
        // Prevent duplicates? Maybe yes.
        final exists = p.songs.any((s) => s.id == song.id || s.url == song.url);
        if (exists) return p;
        return p.copyWith(songs: [...p.songs, song]);
      }
      return p;
    }).toList();
    await _savePlaylists();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    state = state.map((p) {
      if (p.id == playlistId) {
        return p.copyWith(
          songs: p.songs.where((s) => s.id != songId).toList(),
        );
      }
      return p;
    }).toList();
    await _savePlaylists();
  }

  /// Reorders a song within a playlist
  Future<void> reorderSong(String playlistId, int oldIndex, int newIndex) async {
    state = state.map((p) {
      if (p.id == playlistId) {
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        final songs = List<Song>.from(p.songs);
        final Song item = songs.removeAt(oldIndex);
        songs.insert(newIndex, item);
        return p.copyWith(songs: songs);
      }
      return p;
    }).toList();
    await _savePlaylists();
  }
}

final playlistProvider =
    NotifierProvider<PlaylistNotifier, List<Playlist>>(PlaylistNotifier.new);
