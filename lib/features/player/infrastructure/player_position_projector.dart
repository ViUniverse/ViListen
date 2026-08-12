// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/player_clock.dart';

/// Projects complete playback snapshots to the UI at the clock cadence.
///
/// Position candidates are already reduced snapshots. This class only decides
/// when they are visible to UI consumers; it does not rebuild playback state
/// or publish platform metadata.
final class PlayerPositionProjector {
  PlayerPositionProjector({
    required PlayerClock clock,
    PlaybackSnapshot initial = PlaybackSnapshot.idle,
  }) : _lastEmitted = initial {
    _tickSubscription = clock.ticks.listen(_onTick);
  }

  final StreamController<PlaybackSnapshot> _projectionController =
      StreamController<PlaybackSnapshot>.broadcast();

  late final StreamSubscription<Duration> _tickSubscription;

  PlaybackSnapshot _lastEmitted;
  PlaybackSnapshot? _pendingCandidate;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  /// UI snapshots emitted at the cadence supplied by the injected clock.
  Stream<PlaybackSnapshot> get projections => _projectionController.stream;

  /// Retains the newest complete snapshot until the next clock tick.
  void onPositionCandidate(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _pendingCandidate = snapshot;
  }

  /// Emits an immediate snapshot and discards any pending position candidate.
  void onImmediate(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _pendingCandidate = null;
    _emit(snapshot);
  }

  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    _disposed = true;
    final future = _disposeResources();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeResources() async {
    try {
      await _tickSubscription.cancel();
    } finally {
      await _projectionController.close();
    }
  }

  void _onTick(Duration _) {
    final candidate = _pendingCandidate;
    if (_disposed || candidate == null) {
      return;
    }

    _pendingCandidate = null;
    if (candidate == _lastEmitted) {
      return;
    }

    _emit(candidate);
  }

  void _emit(PlaybackSnapshot snapshot) {
    _lastEmitted = snapshot;
    _projectionController.add(snapshot);
  }
}
