import 'package:flutter/material.dart';

class ProgressButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final bool loading;
  final void Function() onTap;
  final bool disabled;

  const ProgressButton({
    required final this.icon,
    required final this.loading,
    required final this.onTap,
    final this.disabled = false,
    final this.color = Colors.white,
    final this.size = 28.0,
  });

  @override
  Widget build(
    final BuildContext context,
  ) {
    final button = IconButton(
      color: color,
      disabledColor: Colors.grey.shade700,
      constraints: const BoxConstraints(),
      padding: EdgeInsets.zero,
      icon: Icon(icon),
      onPressed: !disabled ? onTap : null,
    );
    final progressChild = loading
        ? CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeWidth: 2,
          )
        : const SizedBox.shrink();
    final progress = SizedBox(
      width: size,
      height: size,
      child: progressChild,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        progress,
        Container(child: button),
      ],
    );
  }
}
