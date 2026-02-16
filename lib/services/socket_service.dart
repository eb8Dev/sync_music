import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  late io.Socket socket;

  void connect(String url) {
    socket = io.io(url, {
      'transports': ['websocket'],
      'autoConnect': true,
    });
  }
}
