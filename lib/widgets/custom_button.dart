import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isPrimary;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Theme.of(context).primaryColor : Colors.transparent,
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          side: isPrimary ? null : const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 12),
            ],
            Text(label.toUpperCase()),
          ],
        ),
      ),
    );
  }
}
