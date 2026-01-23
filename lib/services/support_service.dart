import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:flutter/foundation.dart';

class SupportService {
  final InAppReview _inAppReview = InAppReview.instance;

  Future<void> contactSupport() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'eenadulab@gmail.com', // Replace with actual support email
      query: _encodeQueryParameters(<String, String>{
        'subject': 'Sync Music Support Request',
        'body': 'Describe your issue here...',
      }),
    );

    if (!await launchUrl(emailLaunchUri)) {
      debugPrint('Could not launch support email');
    }
  }

  Future<void> requestReview() async {
    if (await _inAppReview.isAvailable()) {
      await _inAppReview.requestReview();
    } else {
      // Fallback: Open store listing directly if needed
      // _inAppReview.openStoreListing(appStoreId: '...', microsoftStoreId: '...');
      debugPrint('In-app review not available');
    }
  }

  String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
}
