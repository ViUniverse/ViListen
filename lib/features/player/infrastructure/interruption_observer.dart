// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/player_logger.dart';

/// The normalized audio-session event observed by [InterruptionObserver].
enum InterruptionObservationKind { begin, end, becomingNoisy }

/// A passive observation of an audio-session interruption or noisy route.
///
/// [latestConfirmedSnapshot] is the most recent snapshot received from the
/// handler's confirmed outward stream when the session event arrived. It is
/// not a prediction of the engine result or a resume-eligibility decision.
final class InterruptionObservation {
  const InterruptionObservation({
    required this.kind,
    required this.interruptionType,
    required this.latestConfirmedSnapshot,
  });

  final InterruptionObservationKind kind;
  final AudioInterruptionType? interruptionType;
  final PlaybackSnapshot latestConfirmedSnapshot;
}

/// Passively records interruption and becoming-noisy events.
///
/// Runtime pause/resume, including conditional resume enforcement, belongs to
/// the `just_audio` owner and device QA. This observer only records the latest
/// confirmed state; it cannot cancel `just_audio`'s private resume eligibility.
/// It deliberately has no playback-command dependency and never calls Play,
/// Pause, or Stop.
final class InterruptionObserver {
  InterruptionObserver({
    required Stream<AudioInterruptionEvent> interruptionEvents,
    required Stream<void> becomingNoisyEvents,
    required Stream<PlaybackSnapshot> confirmedSnapshots,
    PlaybackSnapshot initialSnapshot = PlaybackSnapshot.idle,
    PlayerLogger? logger,
  }) : _latestConfirmedSnapshot = initialSnapshot,
       _logger = logger ?? const PlayerLogger.noop() {
    _subscriptions.add(
      confirmedSnapshots.listen(_onConfirmedSnapshot, onError: _onInputError),
    );
    _subscriptions.add(
      interruptionEvents.listen(_onInterruption, onError: _onInputError),
    );
    _subscriptions.add(
      becomingNoisyEvents.listen(_onBecomingNoisy, onError: _onInputError),
    );
  }

  final StreamController<InterruptionObservation> _observations =
      StreamController<InterruptionObservation>.broadcast(sync: true);
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final PlayerLogger _logger;
  PlaybackSnapshot _latestConfirmedSnapshot;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  Stream<InterruptionObservation> get observations => _observations.stream;

  void _onConfirmedSnapshot(PlaybackSnapshot snapshot) {
    if (!_disposed) {
      _latestConfirmedSnapshot = snapshot;
    }
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (_disposed) {
      return;
    }
    final observation = InterruptionObservation(
      kind: event.begin
          ? InterruptionObservationKind.begin
          : InterruptionObservationKind.end,
      interruptionType: event.type,
      latestConfirmedSnapshot: _latestConfirmedSnapshot,
    );
    _observations.add(observation);
    if (event.begin) {
      _logger.interrupted(
        type: event.type.name,
        itemId: observation.latestConfirmedSnapshot.currentItem?.id,
        positionMs: observation.latestConfirmedSnapshot.position.inMilliseconds,
      );
    }
  }

  void _onBecomingNoisy(void _) {
    if (_disposed) {
      return;
    }
    final observation = InterruptionObservation(
      kind: InterruptionObservationKind.becomingNoisy,
      interruptionType: null,
      latestConfirmedSnapshot: _latestConfirmedSnapshot,
    );
    _observations.add(observation);
    _logger.interrupted(
      type: 'becomingNoisy',
      itemId: observation.latestConfirmedSnapshot.currentItem?.id,
      positionMs: observation.latestConfirmedSnapshot.position.inMilliseconds,
    );
  }

  void _onInputError(Object error, StackTrace stackTrace) {
    if (!_disposed) {
      _observations.addError(error, stackTrace);
    }
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    return _disposeFuture = _disposeResources();
  }

  Future<void> _disposeResources() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    try {
      await Future.wait<void>(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    } finally {
      await _observations.close();
    }
  }
}
