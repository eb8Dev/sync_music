// import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sync_music/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget( PartyApp(showOnboarding: false));

    // Verify that our app starts and shows the buttons.
    expect(find.text('Host Party'), findsOneWidget);
    expect(find.text('Join Party'), findsOneWidget);
  });
}