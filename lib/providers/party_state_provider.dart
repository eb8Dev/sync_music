import 'dart:async';
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
  final int? countdown;

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
    this.countdown,
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
    int? countdown,
    bool clearCountdown = false,
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
      countdown: clearCountdown ? null : (countdown ?? this.countdown),
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
    _cleanupListeners(); // Remove any existing listeners first
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

  void _cleanupListeners() {
    _socket.off("QUEUE_UPDATED", _onQueueUpdated);
    _socket.off("PLAYBACK_UPDATE", _onPlaybackUpdate);
    _socket.off("SYNC", _onSync);
    _socket.off("PARTY_SIZE", _onPartySize);
    _socket.off("VOTE_UPDATE", _onVoteUpdate);
    _socket.off("CHAT_MESSAGE", _onChatMessage);
    _socket.off("INFO", _onInfo);
    _socket.off("MEMBERS_LIST", _onMembersList);
    _socket.off("THEME_UPDATE", _onThemeUpdate);
    _socket.off("HOST_UPDATE", _onHostUpdate);
    // Note: Disconnect/Connect handlers are tricky with Socket.IO client dart 
    // as it doesn't support named handler removal for built-in events easily
    // without exact reference, but our main issue is custom events.
    // For now, we leave connect/disconnect as they just update a bool flag.
  }

  void _setupListeners() {
    _socket.on("QUEUE_UPDATED", _onQueueUpdated);
    _socket.on("PLAYBACK_UPDATE", _onPlaybackUpdate);
    _socket.on("SYNC", _onSync);
    _socket.on("PARTY_SIZE", _onPartySize);
    _socket.on("VOTE_UPDATE", _onVoteUpdate);
    _socket.on("CHAT_MESSAGE", _onChatMessage);
    _socket.on("INFO", _onInfo);
    _socket.on("MEMBERS_LIST", _onMembersList);
    _socket.on("THEME_UPDATE", _onThemeUpdate);
    _socket.on("HOST_UPDATE", _onHostUpdate);

    // Prevent duplicate connection listeners by checking (if possible) or just accepting
    // that these simple bool toggles are less harmful if duplicated.
    _socket.onDisconnect((_) => state = state.copyWith(isDisconnected: true));
    _socket.onConnect((_) => state = state.copyWith(isDisconnected: false));
  }

  // ---- Handlers ----

  void _onQueueUpdated(data) {
    final newQueue = List.from(data);
    if (newQueue.length > state.queue.length) {
       final newTrack = newQueue.last;
       _addSystemMessage("${newTrack['addedBy'] ?? 'Someone'} added '${newTrack['title']}'");
    }
    state = state.copyWith(queue: newQueue);
  }

  void _onPlaybackUpdate(data) {
    state = state.copyWith(
      isPlaying: data["isPlaying"] == true,
      currentIndex: data["currentIndex"] ?? state.currentIndex,
      startedAt: (data["startedAt"] as num?)?.toInt(),
    );
  }

  void _onSync(data) {
     if (data["currentIndex"] != state.currentIndex) {
        state = state.copyWith(
          currentIndex: data["currentIndex"],
          startedAt: (data["startedAt"] as num?)?.toInt(),
        );
     }
  }

  void _onPartySize(data) {
    state = state.copyWith(partySize: data["size"] ?? 1);
  }

  void _onVoteUpdate(data) {
    state = state.copyWith(
      votesCount: data["votes"] ?? 0,
      votesRequired: data["required"] ?? 0,
    );
  }

  void _onChatMessage(data) {
    debugPrint("Chat message received: $data");
    final text = (data['message'] ?? data['text']) as String?;
    
    if (text == "##COUNTDOWN##") {
       debugPrint("Countdown signal received!");
       // Only start if not already counting down
       if (state.countdown == null) {
          _runCountdownLogic(isHost: false);
       }
       return; 
    }

    final msg = {...Map<String, dynamic>.from(data), 'type': 'user'};
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  void _onInfo(msg) {
    _addSystemMessage(msg.toString());
  }

  void _onMembersList(data) {
    try {
      state = state.copyWith(members: List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint("Error parsing members list: $e");
    }
  }

  void _onThemeUpdate(data) {
    state = state.copyWith(themeIndex: data["themeIndex"] ?? 0);
  }

  void _onHostUpdate(data) {
    final newHostId = data["hostId"];
    final updatedMembers = state.members.map((m) {
      return {...m, 'isHost': m['id'] == newHostId};
    }).toList();
    state = state.copyWith(members: updatedMembers);
    _addSystemMessage("Host has changed!");
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

  void _runCountdownLogic({required bool isHost, String? partyId}) {
    state = state.copyWith(countdown: 5);
    Timer.periodic(const Duration(seconds: 1), (timer) {
      final current = state.countdown ?? 0;
      if (current <= 1) {
        timer.cancel();
        state = state.copyWith(clearCountdown: true);
        if (isHost && partyId != null) {
           play(partyId);
        }
      } else {
        state = state.copyWith(countdown: current - 1);
      }
    });
  }

  // Actions
  void addTrack(String partyId, dynamic track) {
    _socket.emit("ADD_TRACK", {"partyId": partyId, "track": track});
  }

  void play(String partyId) {
    _socket.emit("PLAY", {"partyId": partyId});
  }

  void initiateCountdown(String partyId, String username) {
    sendMessage(partyId, "##COUNTDOWN##", username);
    _runCountdownLogic(isHost: true, partyId: partyId);
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
