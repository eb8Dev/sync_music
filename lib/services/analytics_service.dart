import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    await _analytics.logEvent(name: name, parameters: parameters);
  }

  Future<void> logPartyCreated(String partyId) async {
    await logEvent('party_created', parameters: {'party_id': partyId});
  }

  Future<void> logPartyJoined(String partyId) async {
    await logEvent('party_joined', parameters: {'party_id': partyId});
  }

  Future<void> logSongAdded(String title) async {
    await logEvent('song_added', parameters: {'song_title': title});
  }

  Future<void> logViewHomeScreen() async {
    await logEvent('view_home_screen');
  }

  Future<void> logCampaignTrigger(String campaignName) async {
    await logEvent('trigger_campaign', parameters: {'campaign_name': campaignName});
  }

  Future<void> setUserProperties({required String userId, String? role}) async {
    await _analytics.setUserId(id: userId);
    if (role != null) {
      await _analytics.setUserProperty(name: 'role', value: role);
    }
  }
}
