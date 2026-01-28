import 'package:flutter/material.dart';

class NeonLoader extends StatelessWidget {
  const NeonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.7, end: 1),
        duration: const Duration(seconds: 1),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
            ),
          );
        },
        onEnd: () {},
      ),
    );
  }
}
