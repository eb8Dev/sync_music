import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  late IO.Socket socket;

  void connect(String url) {
    socket = IO.io(url, {
      'transports': ['websocket'],
      'autoConnect': true,
    });
  }
}
