import 'dart:async';

/// Injectable clock seam used by playback position/timeline projectors.
///
/// A production implementation may be backed by a timer. Tests inject a
/// synchronous implementation and advance it explicitly.
abstract interface class PlayerClock {
  Stream<Duration> get ticks;

  Duration get elapsed;

  Future<void> dispose();
}
