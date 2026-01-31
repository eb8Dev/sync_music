import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ButtonVariant {
  primary,
  secondary,
  ghost,
}

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Design system props
  final ButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;
  final bool enableHaptics;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.enableHaptics = true,
  });

  bool get _isDisabled => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color backgroundColor;
    final Color foregroundColor;
    final BorderSide? border;

    switch (variant) {
      case ButtonVariant.primary:
        backgroundColor = theme.primaryColor;
        foregroundColor = Colors.black;
        border = null;
        break;

      case ButtonVariant.secondary:
        backgroundColor = Colors.transparent;
        foregroundColor = Colors.white;
        border = const BorderSide(color: Colors.white24);
        break;

      case ButtonVariant.ghost:
        backgroundColor = Colors.transparent;
        foregroundColor = Colors.white70;
        border = BorderSide.none;
        break;
    }

    final button = ElevatedButton(
      onPressed: _isDisabled
          ? null
          : () {
              if (enableHaptics) {
                HapticFeedback.lightImpact();
              }
              onPressed?.call();
            },
      style: ElevatedButton.styleFrom(
        elevation: variant == ButtonVariant.primary ? 8 : 0,
        shadowColor: variant == ButtonVariant.primary ? backgroundColor.withOpacity(0.4) : Colors.transparent,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor:
            backgroundColor.withValues(alpha: 0.4),
        disabledForegroundColor:
            foregroundColor.withValues(alpha: 0.6),
        side: border,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: _buildContent(),
    );

    return Semantics(
      button: true,
      enabled: !_isDisabled,
      label: label,
      child: fullWidth
          ? SizedBox(width: double.infinity, child: button)
          : button,
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 12),
        ],
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
