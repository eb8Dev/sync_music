import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/services/spotify_service.dart';

class SpotifyGlobalNotifier extends Notifier<bool> {
  final _service = SpotifyService();

  @override
  bool build() {
    _init();
    return false;
  }

  Future<void> _init() async {
    final connected = await _service.isLoggedIn();
    state = connected;
  }

  Future<void> connect() async {
    final success = await _service.login();
    state = success;
  }

  Future<void> disconnect() async {
    await _service.logout();
    state = false;
  }
}

final spotifyProvider = NotifierProvider<SpotifyGlobalNotifier, bool>(SpotifyGlobalNotifier.new);
