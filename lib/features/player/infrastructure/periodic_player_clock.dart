// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'player_clock.dart';
import 'player_policies.dart';

/// Production clock used by playback position and timeline projectors.
///
/// The timer starts lazily when the first subscriber listens to [ticks]. This
/// keeps handler construction side-effect free while preserving the canonical
/// UI cadence from [PlayerPolicies].
final class PeriodicPlayerClock implements PlayerClock {
  PeriodicPlayerClock({Duration cadence = PlayerPolicies.uiPositionCadence})
    : _cadence = cadence {
    if (cadence <= Duration.zero) {
      throw ArgumentError.value(
        cadence,
        'cadence',
        'Cadence must be positive.',
      );
    }
  }

  final Duration _cadence;
  final Stopwatch _stopwatch = Stopwatch();
  late final StreamController<Duration> _controller =
      StreamController<Duration>.broadcast(onListen: _start);

  Timer? _timer;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Stream<Duration> get ticks => _controller.stream;

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    return _disposeFuture = _controller.close();
  }

  void _start() {
    if (_disposed || _timer != null) {
      return;
    }

    _stopwatch.start();
    _timer = Timer.periodic(_cadence, (_) {
      if (!_disposed) {
        _controller.add(_stopwatch.elapsed);
      }
    });
  }
}
