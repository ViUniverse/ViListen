// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/player_clock.dart';
import 'package:vi_listen/features/player/infrastructure/player_policies.dart';

/// Projects complete playback snapshots to the OS timeline cadence.
///
/// Position candidates are coalesced and emitted at most once per OS cadence.
/// Lifecycle snapshots bypass the cadence through [onImmediate]. The projector
/// owns only its clock subscription and never owns the clock itself.
final class SystemTimelineProjector {
  SystemTimelineProjector({
    required PlayerClock clock,
    Duration cadence = PlayerPolicies.osPositionCadence,
    PlaybackSnapshot initial = PlaybackSnapshot.idle,
  }) : _clock = clock,
       _cadence = _validateCadence(cadence),
       _lastEmitted = initial,
       _lastPublicationAt = clock.elapsed {
    _tickSubscription = clock.ticks.listen(_onTick);
  }

  final PlayerClock _clock;
  final Duration _cadence;
  final StreamController<PlaybackSnapshot> _projectionController =
      StreamController<PlaybackSnapshot>.broadcast(sync: true);

  late final StreamSubscription<Duration> _tickSubscription;

  PlaybackSnapshot _lastEmitted;
  PlaybackSnapshot? _pendingCandidate;
  Duration _lastPublicationAt;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  /// Snapshots emitted for OS playback-state publication.
  Stream<PlaybackSnapshot> get projections => _projectionController.stream;

  /// Retains the newest complete snapshot until the OS cadence is reached.
  void onPositionCandidate(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _pendingCandidate = snapshot;
  }

  /// Emits a lifecycle snapshot immediately and clears a pending position.
  void onImmediate(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _pendingCandidate = null;
    _lastPublicationAt = _clock.elapsed;
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

    final elapsed = _clock.elapsed;
    if (elapsed - _lastPublicationAt < _cadence) {
      return;
    }

    _pendingCandidate = null;
    _lastPublicationAt = elapsed;
    if (candidate == _lastEmitted) {
      return;
    }

    _emit(candidate);
  }

  void _emit(PlaybackSnapshot snapshot) {
    _lastEmitted = snapshot;
    _projectionController.add(snapshot);
  }

  static Duration _validateCadence(Duration cadence) {
    if (cadence <= Duration.zero) {
      throw ArgumentError.value(
        cadence,
        'cadence',
        'Cadence must be positive.',
      );
    }
    return cadence;
  }
}
