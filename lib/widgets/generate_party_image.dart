import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<File> generatePartyImage(String partyCode) async {
  // 1️⃣ Load the background image
  final byteData = await rootBundle.load('assets/new_sync_music_background.png');
  final bytes = byteData.buffer.asUint8List();
  final image = await decodeImageFromList(bytes);

  // 2️⃣ Create a canvas to draw
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();

  // Draw the background
  canvas.drawImage(image, Offset.zero, paint);

  // 3️⃣ Draw subtle radial glow behind the text
  final glowPaint = Paint()
    ..shader = ui.Gradient.radial(
      Offset(image.width / 2, image.height / 2),
      180,
      [Colors.white.withOpacity(0.25), Colors.transparent],
    );
  canvas.drawCircle(Offset(image.width / 2, image.height / 2), 180, glowPaint);

  // 4️⃣ Draw app name "Sync Music" above the code
  final appName = "Sync Music";
  final appNamePainter = TextPainter(
    text: TextSpan(
      text: appName,
      style: TextStyle(
        fontSize: 36,
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontFamily: "EduSABeginner",
        shadows: [
          Shadow(blurRadius: 3, color: Colors.black, offset: Offset(2, 2)),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  appNamePainter.layout();
  final xCenterApp = (image.width - appNamePainter.width) / 2;
  final yCenterApp = (image.height / 2) - 80; // slightly above code
  appNamePainter.paint(canvas, Offset(xCenterApp, yCenterApp));

  // 5️⃣ Draw party code with outline
  final text = "CODE: $partyCode";

  // Outline (black)
  final outlinePainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 50,
        color: Colors.black,
        fontWeight: FontWeight.bold,
        fontFamily: "EduSABeginner",
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  outlinePainter.layout();
  final xCenter = (image.width - outlinePainter.width) / 2;
  final yCenter = (image.height - outlinePainter.height) / 2;
  outlinePainter.paint(canvas, Offset(xCenter - 2, yCenter - 2));

  // Main white text with shadow
  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 50,
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontFamily: "EduSABeginner",
        shadows: [
          Shadow(blurRadius: 4, color: Colors.black, offset: Offset(2, 2)),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();
  textPainter.paint(canvas, Offset(xCenter, yCenter));

  // 6️⃣ Add a small music note icon in bottom-right corner
  try {
    final iconData = await rootBundle.load('assets/music_note.png');
    final iconImage = await decodeImageFromList(iconData.buffer.asUint8List());

    // Scale icon down to fit background
    const iconSize = 96.0;
    final dx = image.width - iconSize - 16; // padding from edge
    final dy = image.height - iconSize - 16;

    canvas.drawImageRect(
      iconImage,
      Rect.fromLTWH(0, 0, iconImage.width.toDouble(), iconImage.height.toDouble()),
      Rect.fromLTWH(dx, dy, iconSize, iconSize),
      Paint(),
    );
  } catch (_) {
    // Skip if icon not found
  }

  // 7️⃣ Export to image
  final picture = recorder.endRecording();
  final imgFinal = await picture.toImage(image.width, image.height);
  final byteDataFinal = await imgFinal.toByteData(format: ui.ImageByteFormat.png);

  // 8️⃣ Save to temp directory
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/party_$partyCode.png');
  await file.writeAsBytes(byteDataFinal!.buffer.asUint8List());

  return file;
}
