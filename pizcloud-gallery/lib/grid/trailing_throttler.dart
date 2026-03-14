import 'dart:async';

/// Throttle trailing calls while still running the first one immediately.
class TrailingThrottler {
  TrailingThrottler(this.intervalMs);

  final int intervalMs;

  Timer? _timer;
  bool _queued = false;
  void Function()? _lastFn;

  void schedule(void Function() fn) {
    _lastFn = fn;

    if (_timer != null) {
      _queued = true;
      return;
    }

    fn();

    _timer = Timer(Duration(milliseconds: intervalMs), () {
      _timer = null;
      if (_queued) {
        _queued = false;
        final void Function()? next = _lastFn;
        if (next != null) {
          next();
        }
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _queued = false;
    _lastFn = null;
  }
}
