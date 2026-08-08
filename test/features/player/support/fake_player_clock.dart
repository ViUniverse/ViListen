// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:ten_project_cua_ban/features/player/infrastructure/player_clock.dart';

/// Synchronous clock for cadence tests.
final class FakePlayerClock implements PlayerClock {
  final StreamController<Duration> _controller =
      StreamController<Duration>.broadcast(sync: true);

  Duration _elapsed = Duration.zero;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Stream<Duration> get ticks => _controller.stream;

  @override
  Duration get elapsed => _elapsed;

  int disposeCount = 0;

  /// Advances the clock and synchronously emits the new elapsed value.
  void advance(Duration amount) {
    _checkNotDisposed();
    if (amount.isNegative) {
      throw ArgumentError.value(amount, 'amount', 'Cannot be negative.');
    }

    _elapsed += amount;
    _controller.add(_elapsed);
  }

  @override
  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    _disposed = true;
    disposeCount += 1;
    return _disposeFuture = _controller.close();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FakePlayerClock has been disposed.');
    }
  }
}
