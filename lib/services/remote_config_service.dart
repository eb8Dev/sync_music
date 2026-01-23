import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  static const String _serverUrlKey = 'server_url';
  static const String _defaultServerUrl = "https://sync-music-server.onrender.com";

  Future<void> initialize() async {
    try {
      await _remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));

      await _remoteConfig.setDefaults({
        _serverUrlKey: _defaultServerUrl,
      });

      await _remoteConfig.fetchAndActivate();
      debugPrint("Remote Config initialized. Server URL: ${getServerUrl()}");
    } catch (e) {
      debugPrint("Failed to initialize Remote Config: $e");
    }
  }

  String getServerUrl() {
    return _remoteConfig.getString(_serverUrlKey);
  }
}
