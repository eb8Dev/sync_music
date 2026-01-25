import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:sync_music/providers/socket_provider.dart';
import 'package:sync_music/providers/user_provider.dart';
import 'package:sync_music/services/notification_service.dart';

class PartyState {
  final bool connecting;
  final String? partyId;
  final bool isHost;
  final Map<String, dynamic>? partyData;
  final String? error;
  final String? lastPartyId;

  const PartyState({
    this.connecting = false,
    this.partyId,
    this.isHost = false,
    this.partyData,
    this.error,
    this.lastPartyId,
  });

  PartyState copyWith({
    bool? connecting,
    String? partyId,
    bool? isHost,
    Map<String, dynamic>? partyData,
    String? error,
    String? lastPartyId,
    bool clearLastPartyId = false,
  }) {
    return PartyState(
      connecting: connecting ?? this.connecting,
      partyId: partyId ?? this.partyId,
      isHost: isHost ?? this.isHost,
      partyData: partyData ?? this.partyData,
      error: error,
      lastPartyId: clearLastPartyId ? null : (lastPartyId ?? this.lastPartyId),
    );
  }
}

class PartyNotifier extends Notifier<PartyState> {
  late IO.Socket _socket;
  Timer? _connectionTimeoutTimer;

  @override
  PartyState build() {
    _socket = ref.watch(socketProvider);
    _initListeners();
    _loadLastSession();
    return const PartyState();
  }

  void _initListeners() {
    _socket.off("PARTY_STATE");
    _socket.off("ERROR");
    
    if (!_socket.hasListeners("PARTY_STATE")) {
       _socket.on("PARTY_STATE", (data) {
        debugPrint("PARTY_STATE received: $data");
        _cancelTimeout(); // Success!
        
        final pId = data["id"];
        final hostStatus = data["isHost"] == true;
        
        // Save session
        _saveSession(pId, hostStatus);

        // Notify if first time
        NotificationService().showFirstPartyNotificationIfFirstTime();

        state = state.copyWith(
          connecting: false,
          partyId: pId,
          isHost: hostStatus,
          partyData: Map<String, dynamic>.from(data),
          error: null,
        );
      });
    }

    if (!_socket.hasListeners("ERROR")) {
      _socket.on("ERROR", (msg) {
        debugPrint("SERVER ERROR: $msg");
        _cancelTimeout(); // Error received, stop timer
        state = state.copyWith(
          connecting: false,
          error: msg.toString(),
        );
      });
    }

    if (!_socket.hasListeners("HOST_UPDATE")) {
      _socket.on("HOST_UPDATE", (data) {
        final newHostId = data["hostId"];
        final isNowHost = _socket.id == newHostId;
        if (state.isHost != isNowHost) {
           debugPrint("PartyNotifier: Role changed. isHost: $isNowHost");
           state = state.copyWith(isHost: isNowHost);
           _saveSession(state.partyId!, isNowHost);
        }
      });
    }
  }

  void _startTimeout() {
    _cancelTimeout();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (state.connecting) {
        state = state.copyWith(
          connecting: false,
          error: "Connection timed out. Please check your internet or try restarting the app.",
        );
      }
    });
  }

  void _cancelTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
  }

  Future<void> _loadLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString("lastPartyId");
    final host = prefs.getBool("isHost") ?? false;
    
    state = state.copyWith(lastPartyId: lastId, isHost: host); 
  }

  Future<void> _saveSession(String partyId, bool isHost) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("lastPartyId", partyId);
    await prefs.setBool("isHost", isHost);
    state = state.copyWith(lastPartyId: partyId);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("lastPartyId");
    state = state.copyWith(clearLastPartyId: true);
  }
  
  void clearError() {
    state = PartyState(
      connecting: state.connecting,
      partyId: state.partyId,
      isHost: state.isHost,
      partyData: state.partyData,
      error: null,
      lastPartyId: state.lastPartyId,
    );
  }

  void createParty({
    required String username,
    required String avatar,
    String? name,
    bool isPublic = false,
  }) {
    state = state.copyWith(connecting: true, error: null);
    _startTimeout();
    final userState = ref.read(userProvider);
    _socket.emit("CREATE_PARTY", {
      "userId": userState.userId,
      "username": username,
      "avatar": avatar,
      "name": name,
      "isPublic": isPublic,
    });
  }

  void joinParty({
    required String partyId,
    required String username,
    required String avatar,
  }) {
    state = state.copyWith(connecting: true, error: null);
    _startTimeout();
    final userState = ref.read(userProvider);
    _socket.emit("JOIN_PARTY", {
      "userId": userState.userId,
      "partyId": partyId,
      "username": username,
      "avatar": avatar,
    });
  }

  void reconnectAsHost({
    required String partyId,
    required String username,
    required String avatar,
  }) {
    state = state.copyWith(connecting: true, error: null);
    _startTimeout();
    final userState = ref.read(userProvider);
    _socket.emit("RECONNECT_AS_HOST", {
      "userId": userState.userId,
      "partyId": partyId,
      "username": username,
      "avatar": avatar,
    });
  }
}

final partyProvider = NotifierProvider<PartyNotifier, PartyState>(PartyNotifier.new);