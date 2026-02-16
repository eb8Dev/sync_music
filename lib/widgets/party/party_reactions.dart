import 'package:flutter/material.dart';

class PartyReactions extends StatelessWidget {
  final Function(String) onReaction;

  const PartyReactions({super.key, required this.onReaction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: ["🔥", "❤️", "🎉", "😂", "👋", "💃"].map((emoji) {
          return InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => onReaction(emoji),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          );
        }).toList(),
      ),
    );
  }
}
