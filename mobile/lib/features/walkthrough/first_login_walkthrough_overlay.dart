import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/features/walkthrough/first_login_walkthrough_keys.dart';
import 'package:immich_mobile/features/walkthrough/first_login_walkthrough_provider.dart';

class FirstLoginWalkthroughOverlayHost extends ConsumerStatefulWidget {
  const FirstLoginWalkthroughOverlayHost({super.key});

  @override
  ConsumerState<FirstLoginWalkthroughOverlayHost> createState() => _FirstLoginWalkthroughOverlayHostState();
}

class _FirstLoginWalkthroughOverlayHostState extends ConsumerState<FirstLoginWalkthroughOverlayHost> {
  OverlayEntry? _overlayEntry;

  void _removeOverlayEntry() {
    final OverlayEntry? entry = _overlayEntry;
    if (entry == null) {
      return;
    }
    if (entry.mounted) {
      entry.remove();
    }
    _overlayEntry = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _overlayEntry != null) {
        return;
      }

      final OverlayState? rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
      if (rootOverlay == null) {
        return;
      }

      final providerContainer = ProviderScope.containerOf(context);
      final OverlayEntry entry = OverlayEntry(
        builder: (_) =>
            UncontrolledProviderScope(container: providerContainer, child: const _FirstLoginWalkthroughOverlayLayer()),
      );

      _overlayEntry = entry;
      rootOverlay.insert(entry);
    });
  }

  @override
  void dispose() {
    _removeOverlayEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FirstLoginWalkthroughOverlayLayer extends ConsumerStatefulWidget {
  const _FirstLoginWalkthroughOverlayLayer();

  @override
  ConsumerState<_FirstLoginWalkthroughOverlayLayer> createState() => _FirstLoginWalkthroughOverlayLayerState();
}

class _FirstLoginWalkthroughOverlayLayerState extends ConsumerState<_FirstLoginWalkthroughOverlayLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Timer? _missingTargetWatchdogTimer;
  FirstLoginWalkthroughStep? _watchdogStep;

  static const Duration _missingTargetWatchdogTimeout = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    // Keep controller eager-init; lazy init can be triggered during dispose on a deactivated element.
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _clearMissingTargetWatchdog();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FirstLoginWalkthroughStep? step = ref.watch(firstLoginWalkthroughControllerProvider);
    if (step == null) {
      _clearMissingTargetWatchdog();
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final GlobalKey targetKey = _targetKeyForStep(step);
        final Rect? targetRect = _readTargetRect(targetKey);
        if (targetRect == null) {
          _ensureMissingTargetWatchdog(step);
          return const SizedBox.shrink();
        }
        _clearMissingTargetWatchdog();

        final Size screenSize = MediaQuery.of(context).size;
        final EdgeInsets safeArea = MediaQuery.of(context).padding;
        final double highlightPadding = _highlightPaddingForStep(step);
        const double bubbleWidth = 290;
        final Rect highlightRect = targetRect.inflate(highlightPadding);
        final double pulse = Curves.easeOutCubic.transform(_pulseController.value);
        final double ringSpread = 3 + (pulse * 6);
        final bool placeBubbleAbove = highlightRect.center.dy > (screenSize.height * 0.55);
        final double bubbleLeft = (highlightRect.center.dx - (bubbleWidth / 2)).clamp(
          12.0,
          math.max(12.0, screenSize.width - bubbleWidth - 12),
        );
        final double bubbleTop = (placeBubbleAbove ? highlightRect.top - 90 : highlightRect.bottom + 14).clamp(
          safeArea.top + 10,
          math.max(safeArea.top + 10, screenSize.height - safeArea.bottom - 80),
        );

        return Stack(
          children: [
            IgnorePointer(
              // Legacy behavior used a full pass-through overlay (`ignoring: true` for everything).
              // New behavior keeps visuals pass-through but adds explicit blockers outside the target hole.
              ignoring: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SpotlightMaskPainter(
                        highlightRect: highlightRect,
                        borderRadius: 12,
                        overlayColor: Colors.black.withValues(alpha: 0.58),
                      ),
                    ),
                  ),
                  Positioned(
                    left: highlightRect.left - ringSpread,
                    top: highlightRect.top - ringSpread,
                    width: highlightRect.width + (ringSpread * 2),
                    height: highlightRect.height + (ringSpread * 2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 1.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3 + (pulse * 0.35)),
                            blurRadius: 16 + (pulse * 8),
                            spreadRadius: 2 + (pulse * 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: bubbleLeft,
                    top: bubbleTop,
                    width: bubbleWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.84),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(
                          step.messageKey.tr(namedArgs: {'step': '${step.order}', 'total': '5'}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _OutsideTargetInteractionBlocker(holeRect: highlightRect, screenSize: screenSize),
          ],
        );
      },
    );
  }

  GlobalKey _targetKeyForStep(FirstLoginWalkthroughStep step) {
    return switch (step) {
      FirstLoginWalkthroughStep.dateBrowseYear => walkthroughDateBrowseYearButtonKey,
      FirstLoginWalkthroughStep.dateBrowseMonth => walkthroughDateBrowseMonthButtonKey,
      FirstLoginWalkthroughStep.dateBrowseFirstMonthRow => walkthroughDateBrowseFirstMonthRowKey,
      FirstLoginWalkthroughStep.backupTab => walkthroughBackupTabKey,
      FirstLoginWalkthroughStep.backupSelectButton => walkthroughBackupSelectButtonKey,
    };
  }

  Rect? _readTargetRect(GlobalKey targetKey) {
    final BuildContext? targetContext = targetKey.currentContext;
    if (targetContext == null) {
      return null;
    }
    final RenderObject? renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize || !renderObject.attached) {
      return null;
    }

    final Offset topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  double _highlightPaddingForStep(FirstLoginWalkthroughStep step) {
    return switch (step) {
      FirstLoginWalkthroughStep.backupTab => 16,
      FirstLoginWalkthroughStep.backupSelectButton => 10,
      _ => 8,
    };
  }

  void _ensureMissingTargetWatchdog(FirstLoginWalkthroughStep step) {
    if (_watchdogStep == step && _missingTargetWatchdogTimer != null) {
      return;
    }
    _clearMissingTargetWatchdog();
    _watchdogStep = step;
    _missingTargetWatchdogTimer = Timer(_missingTargetWatchdogTimeout, () {
      if (!mounted) {
        return;
      }
      ref.read(firstLoginWalkthroughControllerProvider.notifier).onTargetMissingTimeout(step);
    });
  }

  void _clearMissingTargetWatchdog() {
    _missingTargetWatchdogTimer?.cancel();
    _missingTargetWatchdogTimer = null;
    _watchdogStep = null;
  }
}

class _SpotlightMaskPainter extends CustomPainter {
  const _SpotlightMaskPainter({required this.highlightRect, required this.borderRadius, required this.overlayColor});

  final Rect highlightRect;
  final double borderRadius;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outerPath = Path()..addRect(Offset.zero & size);
    final Path holePath = Path()..addRRect(RRect.fromRectAndRadius(highlightRect, Radius.circular(borderRadius)));
    final Path maskPath = Path.combine(PathOperation.difference, outerPath, holePath);
    canvas.drawPath(maskPath, Paint()..color = overlayColor);
  }

  @override
  bool shouldRepaint(covariant _SpotlightMaskPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _OutsideTargetInteractionBlocker extends StatelessWidget {
  const _OutsideTargetInteractionBlocker({required this.holeRect, required this.screenSize});

  final Rect holeRect;
  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    final Rect screenRect = Offset.zero & screenSize;
    final Rect safeHoleRect = holeRect.intersect(screenRect);
    if (safeHoleRect.isEmpty) {
      return const Positioned.fill(child: _TapBlocker());
    }

    final double topHeight = safeHoleRect.top.clamp(0.0, screenSize.height);
    final double bottomTop = safeHoleRect.bottom.clamp(0.0, screenSize.height);
    final double middleHeight = math.max(0, bottomTop - topHeight);
    final double leftWidth = safeHoleRect.left.clamp(0.0, screenSize.width);
    final double rightStart = safeHoleRect.right.clamp(0.0, screenSize.width);

    return Stack(
      children: [
        if (topHeight > 0)
          Positioned(left: 0, top: 0, width: screenSize.width, height: topHeight, child: const _TapBlocker()),
        if (bottomTop < screenSize.height)
          Positioned(
            left: 0,
            top: bottomTop,
            width: screenSize.width,
            height: screenSize.height - bottomTop,
            child: const _TapBlocker(),
          ),
        if (middleHeight > 0 && leftWidth > 0)
          Positioned(left: 0, top: topHeight, width: leftWidth, height: middleHeight, child: const _TapBlocker()),
        if (middleHeight > 0 && rightStart < screenSize.width)
          Positioned(
            left: rightStart,
            top: topHeight,
            width: screenSize.width - rightStart,
            height: middleHeight,
            child: const _TapBlocker(),
          ),
      ],
    );
  }
}

class _TapBlocker extends StatelessWidget {
  const _TapBlocker();

  @override
  Widget build(BuildContext context) {
    return const AbsorbPointer(absorbing: true, child: SizedBox.expand());
  }
}
