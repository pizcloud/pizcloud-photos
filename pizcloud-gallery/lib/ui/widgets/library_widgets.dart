import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart'
    hide isCupertino;

import '../utils/platform_utils.dart';
import 'platform_widgets.dart';

class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.autoBackupEnabled,
    required this.onToggleAutoBackup,
  });

  final bool autoBackupEnabled;
  final ValueChanged<bool> onToggleAutoBackup;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(20);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B66FF),
            Color(0xFF6B8CFF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const PizPlatformIcon(
                  materialIcon: Icons.cloud,
                  cupertinoIcon: CupertinoIcons.cloud,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PizCloud Photos',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Automatic backup, safe and fast.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Auto backup',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                PizPlatformSwitch(
                  value: autoBackupEnabled,
                  onChanged: onToggleAutoBackup,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.materialIcon,
    required this.cupertinoIcon,
  });

  final String label;
  final String value;
  final IconData materialIcon;
  final IconData cupertinoIcon;

  @override
  Widget build(BuildContext context) {
    final isCupertinoTarget = isCupertino(context);
    final cardColor = isCupertinoTarget
        ? CupertinoColors.systemGroupedBackground.resolveFrom(context)
        : Theme.of(context).colorScheme.surface;
    final borderColor = isCupertinoTarget
        ? CupertinoColors.separator.resolveFrom(context)
        : Theme.of(context).colorScheme.outlineVariant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PizPlatformIcon(
            materialIcon: materialIcon,
            cupertinoIcon: cupertinoIcon,
            color: isCupertinoTarget ? CupertinoColors.activeBlue : Colors.blue,
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityItem extends StatelessWidget {
  const ActivityItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.materialIcon,
    required this.cupertinoIcon,
  });

  final String title;
  final String subtitle;
  final IconData materialIcon;
  final IconData cupertinoIcon;

  @override
  Widget build(BuildContext context) {
    final isCupertinoTarget = isCupertino(context);
    final borderColor = isCupertinoTarget
        ? CupertinoColors.separator.resolveFrom(context)
        : Theme.of(context).colorScheme.outlineVariant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: PizPlatformIcon(
              materialIcon: materialIcon,
              cupertinoIcon: cupertinoIcon,
              color: Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.materialIcon,
    required this.cupertinoIcon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData materialIcon;
  final IconData cupertinoIcon;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      material: (_, __) => ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(materialIcon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cupertino: (_, __) => SizedBox(
        width: double.infinity,
        child: CupertinoButton.filled(
          onPressed: onPressed,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(cupertinoIcon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class SecondaryActionButton extends StatelessWidget {
  const SecondaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.materialIcon,
    required this.cupertinoIcon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData materialIcon;
  final IconData cupertinoIcon;

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      material: (_, __) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(materialIcon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cupertino: (_, __) => SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          onPressed: onPressed,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          color: CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(cupertinoIcon, size: 18, color: CupertinoColors.activeBlue),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: CupertinoColors.activeBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
