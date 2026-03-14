import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

class PizPlatformIcon extends StatelessWidget {
  const PizPlatformIcon({
    super.key,
    required this.materialIcon,
    required this.cupertinoIcon,
    this.color,
    this.size = 22,
  });

  final IconData materialIcon;
  final IconData cupertinoIcon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      material: (_, __) => Icon(materialIcon, color: color, size: size),
      cupertino: (_, __) => Icon(cupertinoIcon, color: color, size: size),
    );
  }
}

class PizPlatformSwitch extends StatelessWidget {
  const PizPlatformSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      material: (_, __) => Switch(
        value: value,
        onChanged: onChanged,
      ),
      cupertino: (_, __) => CupertinoSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class PizPlatformIconButton extends StatelessWidget {
  const PizPlatformIconButton({
    super.key,
    required this.onPressed,
    required this.materialIcon,
    required this.cupertinoIcon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData materialIcon;
  final IconData cupertinoIcon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      material: (_, __) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(materialIcon),
      ),
      cupertino: (_, __) => CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        minSize: 32,
        child: Icon(cupertinoIcon),
      ),
    );
  }
}
