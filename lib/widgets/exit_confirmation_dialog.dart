import 'package:flutter/material.dart';

Future<bool?> showExitConfirmationDialog(BuildContext context, bool isHost) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text(
        "Leaving Party?",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Text(
        isHost
            ? "If you don't return in 2 mins, host privileges will be transferred. Are you sure you want to continue?"
            : "This action will disconnect you from the party. Are you sure you want to continue?",
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("Leave"),
        ),
      ],
    ),
  );
}
