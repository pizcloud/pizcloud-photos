import 'package:flutter/material.dart';

class PizCloudLogo extends StatelessWidget {
  final double size;
  final dynamic heroTag;

  const PizCloudLogo({super.key, this.size = 100, this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Image(
      image: const AssetImage('assets/pizcloud-logo.png'),
      width: size,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
    );
  }
}
