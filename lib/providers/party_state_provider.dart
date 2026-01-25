import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sync_music/providers/socket_provider.dart';

class DetailedPartyState {
  final List<dynamic> queue;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> members;
  final int currentIndex;
  final bool isPlaying;
  final int? startedAt;
  final int partySize;
  final int themeIndex;
  final int votesCount;
  final int votesRequired;
  final bool isDisconnected;

  const DetailedPartyState({
    this.queue = const [],
    this.messages = const [],
    this.members = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.startedAt,
    this.partySize = 0,
    this.themeIndex = 0,
    this.votesCount = 0,
    this.votesRequired = 0,
    this.isDisconnected = false,
  });

  DetailedPartyState copyWith({
    List<dynamic>? queue,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? members,
    int? currentIndex,
    bool? isPlaying,
    int? startedAt,
    int? partySize,
    int? themeIndex,
    int? votesCount,
    int? votesRequired,
    bool? isDisconnected,
  }) {
    return DetailedPartyState(
      queue: queue ?? this.queue,
      messages: messages ?? this.messages,
      members: members ?? this.members,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      startedAt: startedAt ?? this.startedAt,
      partySize: partySize ?? this.partySize,
      themeIndex: themeIndex ?? this.themeIndex,
      votesCount: votesCount ?? this.votesCount,
      votesRequired: votesRequired ?? this.votesRequired,
      isDisconnected: isDisconnected ?? this.isDisconnected,
    );
  }
}

class PartyScreenNotifier extends Notifier<DetailedPartyState> {
  late IO.Socket _socket;

  @override
  DetailedPartyState build() {
    _socket = ref.watch(socketProvider);
    // Initialize with empty state.
    // In a real app, we might want to initialize with data from partyProvider's partyData if available.
    return const DetailedPartyState();
  }

  void init(Map<String, dynamic> initialData) {
    state = DetailedPartyState(
      queue: List.from(initialData["queue"] ?? []),
      currentIndex: initialData["currentIndex"] ?? 0,
      isPlaying: initialData["isPlaying"] == true,
      startedAt: (initialData["startedAt"] as num?)?.toInt(),
      partySize: initialData["size"] ?? 1,
      themeIndex: initialData["themeIndex"] ?? 0,
      members: initialData["members"] != null 
          ? List<Map<String, dynamic>>.from(initialData["members"]) 
          : const [],
    );
    _setupListeners();
  }

  void _setupListeners() {
    _socket.on("QUEUE_UPDATED", (data) {
      final newQueue = List.from(data);
      if (newQueue.length > state.queue.length) {
         final newTrack = newQueue.last;
         _addSystemMessage("${newTrack['addedBy'] ?? 'Someone'} added '${newTrack['title']}'");
      }
      state = state.copyWith(queue: newQueue);
    });

    _socket.on("PLAYBACK_UPDATE", (data) {
      state = state.copyWith(
        isPlaying: data["isPlaying"] == true,
        currentIndex: data["currentIndex"] ?? state.currentIndex,
        startedAt: (data["startedAt"] as num?)?.toInt(),
      );
    });

    _socket.on("SYNC", (data) {
      // Sync events are usually handled by the player controller directly or to trigger a state update if drift is too much.
      // For now, let's just update the startedAt/index if different.
       if (data["currentIndex"] != state.currentIndex) {
          state = state.copyWith(
            currentIndex: data["currentIndex"],
            startedAt: (data["startedAt"] as num?)?.toInt(),
          );
       }
    });

    _socket.on("PARTY_SIZE", (data) {
      state = state.copyWith(partySize: data["size"] ?? 1);
    });

    _socket.on("VOTE_UPDATE", (data) {
      state = state.copyWith(
        votesCount: data["votes"] ?? 0,
        votesRequired: data["required"] ?? 0,
      );
    });

    _socket.on("CHAT_MESSAGE", (data) {
      final msg = {...Map<String, dynamic>.from(data), 'type': 'user'};
      state = state.copyWith(messages: [...state.messages, msg]);
    });

    _socket.on("INFO", (msg) {
      _addSystemMessage(msg.toString());
    });

    _socket.on("MEMBERS_LIST", (data) {
      try {
        state = state.copyWith(members: List<Map<String, dynamic>>.from(data));
      } catch (e) {
        debugPrint("Error parsing members list: $e");
      }
    });

    _socket.on("THEME_UPDATE", (data) {
      state = state.copyWith(themeIndex: data["themeIndex"] ?? 0);
    });

    _socket.on("HOST_UPDATE", (data) {
      final newHostId = data["hostId"];
      final updatedMembers = state.members.map((m) {
        return {...m, 'isHost': m['id'] == newHostId};
      }).toList();
      state = state.copyWith(members: updatedMembers);
      _addSystemMessage("Host has changed!");
    });

    _socket.onDisconnect((_) => state = state.copyWith(isDisconnected: true));
    _socket.onConnect((_) => state = state.copyWith(isDisconnected: false));
  }

  void _addSystemMessage(String text) {
    final msg = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text,
      'type': 'system',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  // Actions
  void addTrack(String partyId, dynamic track) {
    _socket.emit("ADD_TRACK", {"partyId": partyId, "track": track});
  }

  void play(String partyId) {
    _socket.emit("PLAY", {"partyId": partyId});
  }

  void pause(String partyId) {
    _socket.emit("PAUSE", {"partyId": partyId});
  }

  void changeTrack(String partyId, int index) {
    _socket.emit("CHANGE_INDEX", {"partyId": partyId, "newIndex": index});
  }

  void removeTrack(String partyId, String trackId) {
    _socket.emit("REMOVE_TRACK", {"partyId": partyId, "trackId": trackId});
  }

  void voteSkip(String partyId) {
    _socket.emit("VOTE_SKIP", {"partyId": partyId});
  }

  void sendMessage(String partyId, String text, String username) {
    _socket.emit("SEND_MESSAGE", {
      "partyId": partyId,
      "message": text,
      "username": username,
    });
  }

  void sendReaction(String partyId, String emoji) {
    _socket.emit("SEND_REACTION", {"partyId": partyId, "emoji": emoji});
  }

  void changeTheme(String partyId) {
    final nextIndex = (state.themeIndex + 1) % 5; // Assuming 5 themes
    _socket.emit("CHANGE_THEME", {"partyId": partyId, "themeIndex": nextIndex});
  }

  void kickUser(String partyId, String targetId) {
    _socket.emit("KICK_USER", {"partyId": partyId, "targetId": targetId});
  }
  
  void endParty(String partyId) {
    _socket.emit("END_PARTY", {"partyId": partyId});
  }

  void endTrack(String partyId) {
    _socket.emit("TRACK_ENDED", {"partyId": partyId});
  }
}

final partyStateProvider = NotifierProvider<PartyScreenNotifier, DetailedPartyState>(PartyScreenNotifier.new);
