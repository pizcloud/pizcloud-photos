import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'grid_appearance_config.dart';

class FpsMonitor {
  FpsMonitor({this.maxSamples = 120});

  final int maxSamples;
  final ValueNotifier<double> fps = ValueNotifier<double>(0);

  final Queue<int> _frameDurationsUs = Queue<int>();
  int _sumUs = 0;
  bool _listening = false;

  void start() {
    if (_listening) return;
    _listening = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_listening) return;
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _listening = false;
  }

  void dispose() {
    stop();
    fps.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      final int us = timing.totalSpan.inMicroseconds;
      if (us <= 0) continue;

      _frameDurationsUs.addLast(us);
      _sumUs += us;

      while (_frameDurationsUs.length > maxSamples) {
        _sumUs -= _frameDurationsUs.removeFirst();
      }
    }

    if (_frameDurationsUs.isEmpty) return;
    final double avgUs = _sumUs / _frameDurationsUs.length;
    final double nextFps = 1000000.0 / avgUs;
    if ((fps.value - nextFps).abs() >= 0.1) {
      fps.value = nextFps;
    }
  }
}

class FpsBadge extends StatelessWidget {
  const FpsBadge({super.key, required this.monitor});

  final FpsMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final GridAppearancePalette palette = GridAppearancePalette.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.fpsBadgeBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ValueListenableBuilder<double>(
            valueListenable: monitor.fps,
            builder: (context, value, child) {
              final double clamped = value.clamp(0, 120).toDouble();
              return Text(
                '${clamped.toStringAsFixed(1)} FPS',
                style: TextStyle(
                  color: palette.fpsBadgeText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
