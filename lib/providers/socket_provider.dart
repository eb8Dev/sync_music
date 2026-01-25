import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sync_music/services/remote_config_service.dart';

final socketProvider = Provider<IO.Socket>((ref) {
  final serverUrl = RemoteConfigService().getServerUrl();
  debugPrint("SocketProvider: Connecting to $serverUrl");

  final socket = IO.io(serverUrl, {
    'transports': ['websocket'],
    'autoConnect': true,
    'reconnection': true,
    'reconnectionAttempts': 10,
    'reconnectionDelay': 1000,
  });

  return socket;
});
