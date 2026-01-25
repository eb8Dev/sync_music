import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UserState {
  final String userId;
  final String username;
  final String avatar;

  const UserState({
    this.userId = '',
    this.username = '',
    this.avatar = '🎧',
  });

  UserState copyWith({String? userId, String? username, String? avatar}) {
    return UserState(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
    );
  }
}

class UserNotifier extends Notifier<UserState> {
  @override
  UserState build() {
    _loadUser();
    return const UserState();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString("username") ?? "";
    final avatar = prefs.getString("userAvatar") ?? "🎧";
    
    String? userId = prefs.getString("userId");
    if (userId == null || userId.isEmpty) {
      userId = const Uuid().v4();
      await prefs.setString("userId", userId);
    }
    
    state = UserState(userId: userId, username: username, avatar: avatar);
  }

  Future<void> saveUser(String username, String avatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("username", username);
    await prefs.setString("userAvatar", avatar);
    
    // Ensure userId is present (edge case)
    String? userId = state.userId;
    if (userId.isEmpty) {
        userId = prefs.getString("userId");
        if (userId == null || userId.isEmpty) {
            userId = const Uuid().v4();
            await prefs.setString("userId", userId);
        }
    }
    
    state = UserState(userId: userId, username: username, avatar: avatar);
  }
}

final userProvider = NotifierProvider<UserNotifier, UserState>(UserNotifier.new);