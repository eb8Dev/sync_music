import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sync_music/providers/socket_provider.dart';

class ExploreState {
  final List<dynamic> publicParties;
  final bool isLoading;

  const ExploreState({this.publicParties = const [], this.isLoading = true});

  ExploreState copyWith({List<dynamic>? publicParties, bool? isLoading}) {
    return ExploreState(
      publicParties: publicParties ?? this.publicParties,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ExploreNotifier extends Notifier<ExploreState> {
  late IO.Socket _socket;

  @override
  ExploreState build() {
    _socket = ref.watch(socketProvider);
    _setupListeners();
    // Emit directly to avoid modifying state during build
    _socket.emit("GET_PUBLIC_PARTIES");
    return const ExploreState(isLoading: true);
  }

  void _setupListeners() {
    _socket.on("PUBLIC_PARTIES_LIST", (data) {
      state = state.copyWith(publicParties: data, isLoading: false);
    });
  }

  void fetchParties() {
    state = state.copyWith(isLoading: true);
    _socket.emit("GET_PUBLIC_PARTIES");
  }
}

final exploreProvider = NotifierProvider<ExploreNotifier, ExploreState>(ExploreNotifier.new);
