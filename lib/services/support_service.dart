import 'package:in_app_review/in_app_review.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportService {
  final InAppReview _inAppReview = InAppReview.instance;

  // Replace with your real package name
  static const String _androidPackageName =
      "com.eb.sync_music";

  Future<void> requestReview() async {
    try {
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
      } else {
        await openStoreListing();
      }
    } catch (e) {
      debugPrint("Review error: $e");
      await openStoreListing();
    }
  }

  /// Opens Google Play listing directly
  Future<void> openStoreListing() async {
    final Uri playUri = Uri.parse(
      "https://play.google.com/store/apps/details?id=$_androidPackageName",
    );

    if (!await launchUrl(
      playUri,
      mode: LaunchMode.externalApplication,
    )) {
      debugPrint("Could not open Play Store");
    }
  }
}
