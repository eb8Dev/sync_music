import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class NeonEmptyState extends StatelessWidget {
  final bool isEndOfQueue;

  const NeonEmptyState({super.key, required this.isEndOfQueue});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey("empty"),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha:0.4),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              FontAwesomeIcons.music,
              size: 32,
              color: Theme.of(context).colorScheme.primary.withValues(alpha:0.85),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isEndOfQueue ? "No More Tracks" : "Drop the Next Vibe",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Your party is waiting for a beat",
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha:0.5),
            ),
          ),
        ],
      ),
    );
  }
}
