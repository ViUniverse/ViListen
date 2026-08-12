// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/application/player_command_policies.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/just_audio_playback_engine.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import 'package:vi_listen/features/player/infrastructure/load_generation_guard.dart';
import 'package:vi_listen/features/player/infrastructure/playback_command_coordinator.dart';
import 'package:vi_listen/features/player/infrastructure/playback_contexts.dart';
import 'package:vi_listen/features/player/infrastructure/playback_mappers.dart';
import 'package:vi_listen/features/player/infrastructure/playback_position_policy.dart';
import 'package:vi_listen/features/player/infrastructure/playback_publication_diff.dart';
import 'package:vi_listen/features/player/infrastructure/playback_snapshot_reducer.dart';
import 'package:vi_listen/features/player/infrastructure/periodic_player_clock.dart';
import 'package:vi_listen/features/player/infrastructure/player_clock.dart';
import 'package:vi_listen/features/player/infrastructure/player_failure_mapper.dart';
import 'package:vi_listen/features/player/infrastructure/player_item_mapper.dart';
import 'package:vi_listen/features/player/infrastructure/player_policies.dart';
import 'package:vi_listen/features/player/infrastructure/player_position_projector.dart';
import 'package:vi_listen/features/player/infrastructure/system_playback_state_mapper.dart';
import 'package:vi_listen/features/player/infrastructure/system_timeline_projector.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_command_target.dart';

/// Observes command ingress without coupling the handler to a logging or
/// analytics implementation.
typedef PlaybackCommandObserver =
    void Function(String command, CommandSource source);

/// Audio service owner and internal playback command target.
///
/// Engine stream events are reduced into complete domain snapshots. UI and OS
/// publications are projected from those same snapshots.
final class AppAudioHandler extends audio_service.BaseAudioHandler
    with audio_service.QueueHandler, audio_service.SeekHandler
    implements UiPlaybackCommandTarget {
  factory AppAudioHandler.production({
    PlaybackEngine Function()? engineFactory,
    PlayerClock Function()? clockFactory,
    PlaybackCommandObserver? commandObserver,
  }) {
    final createEngine = engineFactory ?? JustAudioPlaybackEngine.new;
    final createClock = clockFactory ?? PeriodicPlayerClock.new;
    return AppAudioHandler(createEngine(), createClock(), commandObserver);
  }

  AppAudioHandler(
    this._engine, [
    PlayerClock? clock,
    PlaybackCommandObserver? commandObserver,
    PlaybackCommandCoordinator? commandCoordinator,
    PlayerFailureMapper? failureMapper,
    PlayerFailurePlatform Function()? failurePlatformResolver,
  ]) : _clock = clock ?? PeriodicPlayerClock(),
       _commandObserver = commandObserver,
       _commandCoordinator = commandCoordinator ?? PlaybackCommandCoordinator(),
       _failureMapper = failureMapper ?? const PlayerFailureMapper(),
       _failurePlatformResolver =
           failurePlatformResolver ?? _defaultFailurePlatform {
    _positionProjector = PlayerPositionProjector(clock: _clock);
    _systemTimelineProjector = SystemTimelineProjector(clock: _clock);
    _projectionSubscriptions
      ..add(_positionProjector.projections.listen(_onUiProjection))
      ..add(_systemTimelineProjector.projections.listen(_onSystemProjection));
    _bindEngineStreams();
  }

  final PlaybackEngine _engine;
  final PlayerClock _clock;
  final PlaybackCommandObserver? _commandObserver;
  final PlaybackCommandCoordinator _commandCoordinator;
  final PlayerFailureMapper _failureMapper;
  final PlayerFailurePlatform Function() _failurePlatformResolver;
  final StreamController<PlaybackSnapshot> _snapshotController =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final List<StreamSubscription<PlaybackSnapshot>> _projectionSubscriptions =
      <StreamSubscription<PlaybackSnapshot>>[];
  final PlaybackSnapshotReducer _snapshotReducer = PlaybackSnapshotReducer();
  final SystemPlaybackStateMapper _systemPlaybackStateMapper =
      SystemPlaybackStateMapper();
  late final PlayerPositionProjector _positionProjector;
  late final SystemTimelineProjector _systemTimelineProjector;

  PlaybackSnapshot _latestSnapshot = PlaybackSnapshot.idle;
  PlaybackSnapshot _lastSystemPublishedSnapshot = PlaybackSnapshot.idle;
  List<int> _effectiveSequence = const <int>[];
  List<int>? _pendingEffectiveSequence;
  LoadGeneration? _pendingEffectiveSequenceGeneration;
  int? _pendingEffectiveSequenceEpoch;
  ActivePlaybackContext? _active;
  PendingLoadContext? _pending;
  RetryContext? _retryContext;
  _RestoreGraphContext? _restoring;
  _LoadFlight? _activeLoad;
  _PlayPauseIntent? _playPauseIntent;
  double _desiredSpeed = PlaybackSnapshot.idle.speed;
  double _lastConfirmedSpeed = PlaybackSnapshot.idle.speed;
  int _desiredSpeedRevision = 0;
  _SpeedFlight? _speedFlight;
  _SpeedFlight? _queuedSpeedFlight;
  LoadGeneration? _lastAppliedSpeedGeneration;
  int? _lastAppliedSpeedRevision;
  PlayerRepeatMode _desiredRepeatMode = PlaybackSnapshot.idle.repeatMode;
  PlayerRepeatMode _lastConfirmedRepeatMode = PlaybackSnapshot.idle.repeatMode;
  int _desiredRepeatRevision = 0;
  _RepeatFlight? _repeatFlight;
  _RepeatFlight? _queuedRepeatFlight;
  LoadGeneration? _lastAppliedRepeatGeneration;
  int? _lastAppliedRepeatRevision;
  bool _desiredShuffleEnabled = PlaybackSnapshot.idle.shuffleEnabled;
  bool _lastConfirmedShuffleEnabled = PlaybackSnapshot.idle.shuffleEnabled;
  int _desiredShuffleRevision = 0;
  _ShuffleFlight? _shuffleFlight;
  _ShuffleFlight? _queuedShuffleFlight;
  _ShuffleSequenceCandidate? _pendingShuffleCandidate;
  int _effectiveSequenceEpoch = 0;
  int _nextSeekConfirmationSequence = 0;
  _SeekConfirmation? _pendingSeekConfirmation;
  int _nextPlayPauseSequence = 0;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @visibleForTesting
  RetryContext? get retryContext => _retryContext;

  @override
  Stream<PlaybackSnapshot> get snapshots =>
      Stream<PlaybackSnapshot>.multi((subscriber) {
        if (_disposed) {
          subscriber.close();
          return;
        }

        final replay = _latestSnapshot;
        var cancelled = false;
        final sourceSubscription = _snapshotController.stream.listen(
          subscriber.add,
          onError: (Object error, StackTrace stackTrace) {
            subscriber.addError(error, stackTrace);
          },
          onDone: subscriber.close,
        );
        subscriber.onCancel = () {
          cancelled = true;
          return sourceSubscription.cancel();
        };

        scheduleMicrotask(() {
          if (!_disposed && !cancelled && !subscriber.isClosed) {
            subscriber.addSync(replay);
          }
        });
      }, isBroadcast: true);

  void _bindEngineStreams() {
    _subscriptions
      ..add(_engine.playerStateStream.listen(_onPlayerState))
      ..add(_engine.positionStream.listen(_onPosition))
      ..add(_engine.bufferedPositionStream.listen(_onBufferedPosition))
      ..add(_engine.durationStream.listen(_onDuration))
      ..add(_engine.currentIndexStream.listen(_onCurrentIndex))
      ..add(_engine.effectiveSequenceStream.listen(_onEffectiveSequence))
      ..add(_engine.speedStream.listen(_onSpeed))
      ..add(_engine.loopModeStream.listen(_onLoopMode))
      ..add(_engine.shuffleModeEnabledStream.listen(_onShuffleEnabled));
    // Source-load errors are owned by the corresponding load Future. This
    // untagged stream is runtime-only so a delayed A error cannot target B.
    _subscriptions.add(_engine.errorStream.listen(_onEngineError));
  }

  static PlayerFailurePlatform _defaultFailurePlatform() {
    if (kIsWeb) {
      return PlayerFailurePlatform.web;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => PlayerFailurePlatform.android,
      TargetPlatform.iOS || TargetPlatform.macOS => PlayerFailurePlatform.apple,
      _ => PlayerFailurePlatform.unknown,
    };
  }

  void _onEngineError(just_audio.PlayerException error) {
    if (_disposed || _hasSourceTransaction) {
      return;
    }

    final active = _active;
    final snapshot = _snapshotReducer.latest;
    final item = snapshot.currentItem;
    if (active == null || item == null) {
      return;
    }

    final logicalIndex = active.logicalQueue.indexOf(item);
    if (logicalIndex < 0) {
      return;
    }
    _publishFailure(
      error,
      context: PlayerFailureContext.runtime,
      itemId: item.id,
      retryContext: RetryContext(
        targetQueue: active.logicalQueue,
        targetIndex: logicalIndex,
        restorePosition: snapshot.position,
        desiredPlaying: active.desiredPlaying,
        failureGeneration: null,
        failureItemId: item.id,
      ),
    );
  }

  bool get _hasSourceTransaction =>
      _pending != null || _restoring != null || _activeLoad != null;

  void _onPlayerState(just_audio.PlayerState state) {
    if (_routeToCurrentLoad((events) => events.onPlayerState(state))) {
      return;
    }
    _reconcilePlayPauseConfirmation(state.playing);
    _reduceAndPublish(() => _snapshotReducer.onPlayerState(state));
  }

  void _onPosition(Duration position) {
    if (_routeToCurrentLoad((events) => events.onPosition(position))) {
      return;
    }
    if (_disposed) {
      return;
    }

    final candidate = _snapshotReducer.onPosition(position);
    final confirmation = _pendingSeekConfirmation;
    if (confirmation != null &&
        position == confirmation.target &&
        _commandCoordinator.isSourceTokenCurrent(confirmation.sourceToken)) {
      _pendingSeekConfirmation = null;
      _positionProjector.onImmediate(candidate);
      _systemTimelineProjector.onImmediate(candidate);
      return;
    }

    _positionProjector.onPositionCandidate(candidate);
    _systemTimelineProjector.onPositionCandidate(candidate);
  }

  void _onBufferedPosition(Duration bufferedPosition) {
    if (_routeToCurrentLoad(
      (events) => events.onBufferedPosition(bufferedPosition),
    )) {
      return;
    }
    _reduceAndPublish(
      () => _snapshotReducer.onBufferedPosition(bufferedPosition),
    );
  }

  void _onDuration(Duration? duration) {
    if (_routeToCurrentLoad((events) => events.onDuration(duration))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onDuration(duration));
  }

  void _onCurrentIndex(int? currentIndex) {
    if (_routeToCurrentLoad((events) => events.onCurrentIndex(currentIndex))) {
      return;
    }
    if (_shuffleFlight != null) {
      return;
    }
    final effectiveIndex = _toEffectiveIndex(currentIndex);
    _reduceAndPublish(() => _snapshotReducer.onCurrentIndex(effectiveIndex));
  }

  void _onEffectiveSequence(List<int> sequence) {
    if (_disposed) {
      return;
    }

    final eventEpoch = ++_effectiveSequenceEpoch;

    final restoring = _restoring;
    if (restoring != null) {
      if (_commandCoordinator.isSourceTokenCurrent(restoring.sourceToken)) {
        restoring.recordEffectiveSequence(sequence);
      }
      return;
    }

    final pending = _pending;
    final shuffleFlight = _shuffleFlight;
    if (shuffleFlight != null) {
      final pendingShuffle =
          pending != null &&
          shuffleFlight.generation == pending.generation &&
          shuffleFlight.revision == _desiredShuffleRevision &&
          shuffleFlight.enabled == _desiredShuffleEnabled;
      final logicalQueue =
          pending?.targetQueue ??
          _active?.logicalQueue ??
          _snapshotReducer.latest.queue;

      if (pendingShuffle &&
          shuffleFlight.dispatched &&
          eventEpoch > shuffleFlight.sequenceEpochAtDispatch &&
          _isShuffleSequenceValid(
            sequence,
            queueLength: logicalQueue.length,
            enabled: shuffleFlight.enabled,
          )) {
        shuffleFlight.sequenceCandidate = _ShuffleSequenceCandidate(
          sequence: sequence,
          revision: shuffleFlight.revision,
          generation: shuffleFlight.generation,
          eventEpoch: eventEpoch,
        );
        if (!shuffleFlight.sequenceConfirmation.isCompleted) {
          shuffleFlight.sequenceConfirmation.complete();
        }
        _tryCommitShuffleFlight(shuffleFlight);
        return;
      }

      if (!shuffleFlight.dispatched ||
          shuffleFlight.revision != _desiredShuffleRevision ||
          (shuffleFlight.generation != null &&
              shuffleFlight.generation != pending?.generation) ||
          eventEpoch <= shuffleFlight.sequenceEpochAtDispatch) {
        return;
      }

      if (!_isShuffleSequenceValid(
        sequence,
        queueLength: logicalQueue.length,
        enabled: shuffleFlight.enabled,
      )) {
        return;
      }

      shuffleFlight.sequenceCandidate = _ShuffleSequenceCandidate(
        sequence: sequence,
        revision: shuffleFlight.revision,
        generation: shuffleFlight.generation,
        eventEpoch: eventEpoch,
      );
      if (!shuffleFlight.sequenceConfirmation.isCompleted) {
        shuffleFlight.sequenceConfirmation.complete();
      }
      _tryCommitShuffleFlight(shuffleFlight);
      return;
    }

    if (pending != null) {
      if (_commandCoordinator.isCurrent(pending.generation)) {
        _pendingEffectiveSequence = List<int>.unmodifiable(sequence);
        _pendingEffectiveSequenceGeneration = pending.generation;
        _pendingEffectiveSequenceEpoch = eventEpoch;
      }
      return;
    }

    final active = _active;
    final logicalQueue = active?.logicalQueue ?? _latestSnapshot.queue;
    final effectiveQueue = _effectiveQueue(logicalQueue, sequence);
    if (effectiveQueue == null) {
      return;
    }

    _effectiveSequence = List<int>.unmodifiable(sequence);
    final currentItem = _snapshotReducer.latest.currentItem;
    final logicalIndex = currentItem == null
        ? null
        : logicalQueue.indexOf(currentItem);
    final effectiveIndex = _toEffectiveIndex(logicalIndex, sequence: sequence);
    final reduced = _snapshotReducer.commitQueue(
      effectiveQueue,
      currentIndex: effectiveIndex,
    );
    _updateActiveQueue(effectiveQueue, reduced.currentIndex);
    _routeImmediate(reduced);
  }

  void _onSpeed(double speed) {
    if (_disposed) {
      return;
    }

    final flight = _speedFlight;
    if (flight != null) {
      // Engine streams do not carry a command token. While a newer desired
      // value exists, a different value can only be a stale confirmation.
      if (!flight.dispatched || flight.speed != speed) {
        return;
      }

      _lastConfirmedSpeed = speed;
      flight.confirmed = true;
      if (!flight.confirmation.isCompleted) {
        flight.confirmation.complete();
      }

      final pending = _currentPendingLoad();
      if (pending != null && flight.generation == pending.generation) {
        pending.engineEvents.onSpeed(speed);
        _lastAppliedSpeedGeneration = pending.generation;
        _lastAppliedSpeedRevision = flight.revision;
      } else if (pending == null) {
        _reduceAndPublish(() => _snapshotReducer.onSpeed(speed));
      }

      _maybeFinalizeSpeedFlight(flight);
      return;
    }

    // Once a caller has established a desired speed, an untagged engine event
    // with another value is stale. Do not let it enter a newer load context or
    // overwrite the confirmed outward state.
    if (_desiredSpeedRevision > 0 && speed != _desiredSpeed) {
      return;
    }

    _lastConfirmedSpeed = speed;
    final pending = _currentPendingLoad();
    if (pending != null && _desiredSpeedRevision > 0) {
      // This event has no current speed-flight generation. It may belong to an
      // older load, so the current load must reapply and confirm its desired
      // speed before commit.
      return;
    }
    if (_routeToCurrentLoad((events) => events.onSpeed(speed))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onSpeed(speed));
  }

  void _onLoopMode(just_audio.LoopMode loopMode) {
    if (_disposed) {
      return;
    }

    final mode = PlaybackMappers.fromEngineRepeat(loopMode);
    final flight = _repeatFlight;
    final pending = _currentPendingLoad();
    if (flight != null) {
      if (!flight.dispatched ||
          flight.revision != _desiredRepeatRevision ||
          flight.mode != _desiredRepeatMode ||
          flight.mode != mode) {
        return;
      }
      if (pending != null && flight.generation != pending.generation) {
        // An untagged loop event from the previous graph cannot confirm the
        // current load. The current generation must reapply and confirm it.
        return;
      }

      _lastConfirmedRepeatMode = mode;
      flight.confirmed = true;
      if (!flight.confirmation.isCompleted) {
        flight.confirmation.complete();
      }

      if (pending != null) {
        pending.engineEvents.onLoopMode(loopMode);
        _lastAppliedRepeatGeneration = pending.generation;
        _lastAppliedRepeatRevision = flight.revision;
      } else {
        _reduceAndPublish(() => _snapshotReducer.onLoopMode(loopMode));
      }

      _maybeFinalizeRepeatFlight(flight);
      return;
    }

    // Once a desired repeat mode exists, an untagged event with another mode
    // can only be stale. Do not let it overwrite the confirmed outward state.
    if (_desiredRepeatRevision > 0 && mode != _desiredRepeatMode) {
      return;
    }

    _lastConfirmedRepeatMode = mode;
    if (pending != null && _desiredRepeatRevision > 0) {
      // A current load with a desired option must reapply it through a
      // generation-bound flight before its snapshot can be committed.
      return;
    }
    if (_routeToCurrentLoad((events) => events.onLoopMode(loopMode))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onLoopMode(loopMode));
  }

  void _onShuffleEnabled(bool enabled) {
    if (_disposed) {
      return;
    }

    final flight = _shuffleFlight;
    final pending = _currentPendingLoad();
    if (flight != null) {
      if (!flight.dispatched ||
          flight.revision != _desiredShuffleRevision ||
          flight.enabled != _desiredShuffleEnabled ||
          flight.enabled != enabled) {
        return;
      }
      if (pending != null && flight.generation != pending.generation) {
        return;
      }

      _lastConfirmedShuffleEnabled = enabled;
      flight.modeConfirmed = true;
      if (!flight.modeConfirmation.isCompleted) {
        flight.modeConfirmation.complete();
      }

      if (pending != null) {
        pending.engineEvents.onShuffleEnabled(enabled);
      } else {
        _tryCommitShuffleFlight(flight);
      }
      return;
    }

    if (_desiredShuffleRevision > 0 && enabled != _desiredShuffleEnabled) {
      return;
    }

    _lastConfirmedShuffleEnabled = enabled;
    if (_routeToCurrentLoad((events) => events.onShuffleEnabled(enabled))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onShuffleEnabled(enabled));
  }

  bool _routeToPending(void Function(PendingLoadAccumulator events) update) {
    if (_disposed) {
      return true;
    }

    final pending = _pending;
    if (pending == null) {
      return false;
    }

    if (!_commandCoordinator.isCurrent(pending.generation)) {
      return true;
    }

    update(pending.engineEvents);
    return true;
  }

  bool _routeToCurrentLoad(
    void Function(PendingLoadAccumulator events) update,
  ) {
    final restoring = _restoring;
    if (restoring != null) {
      if (_commandCoordinator.isSourceTokenCurrent(restoring.sourceToken)) {
        update(restoring.engineEvents);
      }
      return true;
    }
    return _routeToPending(update);
  }

  void _reduceAndPublish(PlaybackSnapshot Function() reduce) {
    if (_disposed) {
      return;
    }

    final reduced = reduce();
    final diff = PlaybackPublicationDiff.between(
      previous: _latestSnapshot,
      current: reduced,
    );

    if (!diff.snapshotChanged) {
      return;
    }

    _routeImmediate(reduced);
  }

  void _routeImmediate(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    _positionProjector.onImmediate(snapshot);
    _systemTimelineProjector.onImmediate(snapshot);
  }

  void _onUiProjection(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    final diff = PlaybackPublicationDiff.between(
      previous: _latestSnapshot,
      current: snapshot,
    );
    _latestSnapshot = snapshot;
    if (diff.snapshotChanged) {
      _snapshotController.add(snapshot);
    }
  }

  void _onSystemProjection(PlaybackSnapshot snapshot) {
    if (_disposed) {
      return;
    }

    final diff = PlaybackPublicationDiff.between(
      previous: _lastSystemPublishedSnapshot,
      current: snapshot,
    );
    _lastSystemPublishedSnapshot = snapshot;
    if (!diff.snapshotChanged) {
      return;
    }

    if (diff.queueChanged) {
      queue.add(_toMediaItems(snapshot.queue));
    }
    if (diff.mediaItemChanged) {
      final currentItem = snapshot.currentItem;
      mediaItem.add(
        currentItem == null ? null : PlayerItemMapper.toMediaItem(currentItem),
      );
    }
    if (diff.playbackStateChanged) {
      playbackState.add(_systemPlaybackStateMapper.map(snapshot));
    }
  }

  static List<audio_service.MediaItem> _toMediaItems(
    Iterable<PlayerItem> items,
  ) => List<audio_service.MediaItem>.unmodifiable(
    items.map(PlayerItemMapper.toMediaItem),
  );

  void _rememberActiveContext() {
    if (_active != null || _latestSnapshot.queue.isEmpty) {
      return;
    }

    _active = ActivePlaybackContext.fromSnapshot(
      logicalQueue: _latestSnapshot.queue,
      effectiveQueue: _latestSnapshot.queue,
      currentIndex: _latestSnapshot.currentIndex,
      position: _latestSnapshot.position,
      desiredPlaying: _latestSnapshot.playing,
    );
  }

  PendingLoadContext? _currentPendingLoad() {
    final pending = _pending;
    if (pending == null || !_commandCoordinator.isCurrent(pending.generation)) {
      return null;
    }
    return pending;
  }

  void _setActiveDesiredPlaying(bool desiredPlaying) {
    final active = _active;
    if (active == null) {
      return;
    }

    _active = ActivePlaybackContext(
      logicalQueue: active.logicalQueue,
      effectiveQueue: active.effectiveQueue,
      currentIndex: active.currentIndex,
      position: active.position,
      desiredPlaying: desiredPlaying,
    );
  }

  void _updateActiveQueue(List<PlayerItem> effectiveQueue, int? currentIndex) {
    final active = _active;
    if (active == null) {
      return;
    }

    _active = ActivePlaybackContext(
      logicalQueue: active.logicalQueue,
      effectiveQueue: effectiveQueue,
      currentIndex: currentIndex,
      position: active.position,
      desiredPlaying: active.desiredPlaying,
    );
  }

  int? _toEffectiveIndex(
    int? logicalIndex, {
    List<int>? sequence,
    int? queueLength,
  }) {
    if (logicalIndex == null || logicalIndex < 0) {
      return null;
    }

    final length = queueLength ?? _snapshotReducer.latest.queue.length;
    if (logicalIndex >= length) {
      return null;
    }

    final resolvedSequence = _validEffectiveSequence(
      sequence ?? _effectiveSequence,
      length,
    );
    if (resolvedSequence == null) {
      return logicalIndex;
    }

    final effectiveIndex = resolvedSequence.indexOf(logicalIndex);
    return effectiveIndex < 0 ? null : effectiveIndex;
  }

  int _toLogicalEngineIndex({
    required int effectiveIndex,
    required PlayerItem item,
  }) {
    final active = _active;
    if (active != null &&
        effectiveIndex >= 0 &&
        effectiveIndex < active.effectiveQueue.length &&
        active.effectiveQueue[effectiveIndex] == item) {
      final logicalIndex = active.logicalQueue.indexOf(item);
      if (logicalIndex >= 0) {
        return logicalIndex;
      }
    }

    final logicalLength =
        active?.logicalQueue.length ?? _snapshotReducer.latest.queue.length;
    final sequence = _validEffectiveSequence(_effectiveSequence, logicalLength);
    if (sequence != null &&
        effectiveIndex >= 0 &&
        effectiveIndex < sequence.length) {
      return sequence[effectiveIndex];
    }
    return effectiveIndex;
  }

  static List<PlayerItem>? _effectiveQueue(
    Iterable<PlayerItem> logicalQueue,
    Iterable<int> sequence,
  ) {
    final logicalItems = List<PlayerItem>.unmodifiable(logicalQueue);
    final resolvedSequence = _validEffectiveSequence(
      sequence,
      logicalItems.length,
    );
    if (resolvedSequence == null) {
      return null;
    }

    return List<PlayerItem>.unmodifiable(
      resolvedSequence.map((index) => logicalItems[index]),
    );
  }

  static List<int>? _validEffectiveSequence(
    Iterable<int>? sequence,
    int queueLength,
  ) {
    if (sequence == null) {
      return null;
    }

    final indexes = List<int>.unmodifiable(sequence);
    if (indexes.length != queueLength) {
      return null;
    }

    final seen = <int>{};
    for (final index in indexes) {
      if (index < 0 || index >= queueLength || !seen.add(index)) {
        return null;
      }
    }
    return indexes;
  }

  static List<int> _identitySequence(int length) =>
      List<int>.unmodifiable(List<int>.generate(length, (index) => index));

  @override
  Future<void> handleLoadQueue(
    List<PlayerItem> items,
    int initialIndex,
    bool autoplay,
    CommandSource source,
  ) async {
    _notifyCommandObserver('loadQueue', source);

    final validatedItems = PlayerPolicies.validateQueue(
      items,
      initialIndex: initialIndex,
      isWeb: kIsWeb,
    );

    // Source-changing commands invalidate local intent records immediately
    // after validation succeeds. The coordinator performs the corresponding
    // platform-side invalidation before the new graph transaction starts.
    _retryContext = null;
    _playPauseIntent = null;
    _pendingSeekConfirmation = null;
    _invalidateActiveShuffleFlight();

    await _commandCoordinator.load((generation) async {
      if (_disposed) {
        return;
      }

      _rememberActiveContext();
      final pending = PendingLoadContext.fromItems(
        items: validatedItems,
        targetIndex: initialIndex,
        autoplay: autoplay,
        generation: generation,
      );
      _pending = pending;
      _pendingEffectiveSequence = null;
      _pendingEffectiveSequenceGeneration = null;
      _pendingEffectiveSequenceEpoch = null;
      _pendingShuffleCandidate = null;

      // Keep the active tuple outward during replacement. For an initial load
      // the reducer's canonical tuple is already empty. Pending projections
      // stay internal until a later load-commit task confirms this generation.
      _reduceAndPublish(_snapshotReducer.onLoadStarted);

      final flight = _LoadFlight(generation: generation);
      _activeLoad = flight;
      try {
        final engineLoad = _engine.load(
          pending.sources,
          initialIndex: pending.targetIndex,
        );
        unawaited(
          engineLoad.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );

        try {
          await Future.any<void>([engineLoad, flight.interrupted]);
        } catch (error, stackTrace) {
          if (!_commandCoordinator.isCurrent(generation)) {
            return;
          }
          _handleCurrentLoadFailure(
            error,
            pending: pending,
            generation: generation,
          );
          Error.throwWithStackTrace(error, stackTrace);
        }
        // PLR-063 will commit only this still-current context. Keep the check at
        // the load boundary so a stale completion cannot accidentally become a
        // publication when that commit path is added.
        if (_disposed ||
            !identical(_pending, pending) ||
            !_commandCoordinator.isCurrent(generation)) {
          return;
        }

        await _preparePendingSpeed(pending, flight);
        await _preparePendingRepeat(pending, flight);
        await _preparePendingShuffle(pending, flight);

        if (_disposed ||
            !identical(_pending, pending) ||
            !_commandCoordinator.isCurrent(generation)) {
          return;
        }

        _commitPendingLoad(pending);

        if (pending.desiredPlaying &&
            _commandCoordinator.isCurrent(generation)) {
          _startAutoplay(generation);
        }
      } finally {
        if (identical(_activeLoad, flight)) {
          _activeLoad = null;
        }
      }
    }, interrupt: _interruptCurrentLoad);
  }

  void _commitPendingLoad(PendingLoadContext pending) {
    final events = pending.engineEvents;
    final pendingSequence =
        _pendingEffectiveSequenceGeneration == pending.generation &&
            _pendingEffectiveSequenceEpoch != null &&
            _pendingEffectiveSequenceEpoch! <= _effectiveSequenceEpoch
        ? _pendingEffectiveSequence
        : null;
    final committedSequence =
        _committedShuffleSequence(pending) ??
        _validEffectiveSequence(pendingSequence, pending.targetQueue.length) ??
        _identitySequence(pending.targetQueue.length);
    final effectiveQueue = _effectiveQueue(
      pending.targetQueue,
      committedSequence,
    )!;
    final eventIndex = events.currentIndex;
    final logicalIndex =
        events.hasCurrentIndex &&
            eventIndex != null &&
            eventIndex >= 0 &&
            eventIndex < pending.targetQueue.length
        ? eventIndex
        : pending.targetIndex;
    final currentIndex = _toEffectiveIndex(
      logicalIndex,
      sequence: committedSequence,
      queueLength: pending.targetQueue.length,
    );

    _snapshotReducer.commitQueue(effectiveQueue, currentIndex: currentIndex);
    if (events.hasPosition) {
      _snapshotReducer.onPosition(events.position!);
    }
    if (events.hasBufferedPosition) {
      _snapshotReducer.onBufferedPosition(events.bufferedPosition!);
    }
    if (events.hasDuration) {
      _snapshotReducer.onDuration(events.duration);
    }
    if (_desiredSpeedRevision > 0) {
      if (_lastConfirmedSpeed == _desiredSpeed) {
        _snapshotReducer.onSpeed(_desiredSpeed);
      }
    } else if (events.hasSpeed) {
      _snapshotReducer.onSpeed(events.speed!);
    }
    if (_desiredRepeatRevision > 0) {
      final repeatPrepared =
          _lastAppliedRepeatGeneration == pending.generation &&
          _lastAppliedRepeatRevision == _desiredRepeatRevision &&
          _lastConfirmedRepeatMode == _desiredRepeatMode;
      if (!repeatPrepared) {
        throw StateError(
          'Pending repeat mode was not confirmed for the current load.',
        );
      }
      _snapshotReducer.onLoopMode(
        PlaybackMappers.toEngineRepeat(_desiredRepeatMode),
      );
    } else if (events.hasLoopMode) {
      _lastConfirmedRepeatMode = PlaybackMappers.fromEngineRepeat(
        events.loopMode!,
      );
      _snapshotReducer.onLoopMode(events.loopMode!);
    }
    if (_desiredShuffleRevision > 0) {
      final shufflePrepared = _pendingShuffleCandidate;
      if (!_isPendingShuffleCandidateValid(
            shufflePrepared,
            pending,
            committedSequence,
          ) ||
          _lastConfirmedShuffleEnabled != _desiredShuffleEnabled) {
        throw StateError(
          'Pending shuffle mode and effective sequence were not confirmed.',
        );
      }
      _snapshotReducer.onShuffleEnabled(_desiredShuffleEnabled);
    } else if (events.hasShuffleEnabled) {
      _snapshotReducer.onShuffleEnabled(events.shuffleEnabled!);
    }

    // Load is prepare-only. A pending player-state event cannot confirm
    // autoplay, so every successful load is committed as ready and paused.
    final committed = _snapshotReducer.onPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    final committedShuffleCandidate = _pendingShuffleCandidate;
    final committedShuffleFlight = _shuffleFlight;
    if (committedShuffleFlight != null &&
        committedShuffleFlight.generation == pending.generation &&
        identical(
          committedShuffleFlight.sequenceCandidate,
          committedShuffleCandidate,
        )) {
      committedShuffleFlight.committed = true;
    }

    _pending = null;
    _pendingEffectiveSequence = null;
    _pendingEffectiveSequenceGeneration = null;
    _pendingEffectiveSequenceEpoch = null;
    _pendingShuffleCandidate = null;
    _effectiveSequence = committedSequence;
    _active = ActivePlaybackContext(
      logicalQueue: pending.targetQueue,
      effectiveQueue: effectiveQueue,
      currentIndex: committed.currentIndex,
      position: committed.position,
      desiredPlaying: pending.desiredPlaying,
    );

    _routeImmediate(committed);
    _maybeFinalizeShuffleFlight(_shuffleFlight);
  }

  void _handleCurrentLoadFailure(
    Object error, {
    required PendingLoadContext pending,
    required LoadGeneration generation,
  }) {
    if (_disposed ||
        !identical(_pending, pending) ||
        !_commandCoordinator.isCurrent(generation)) {
      return;
    }

    final target = pending.targetQueue[pending.targetIndex];
    final active = _active;
    final context = active == null
        ? PlayerFailureContext.initialLoad
        : PlayerFailureContext.replaceLoad;
    final retry = RetryContext(
      targetQueue: pending.targetQueue,
      targetIndex: pending.targetIndex,
      restorePosition: Duration.zero,
      desiredPlaying: pending.desiredPlaying,
      failureGeneration: generation,
      failureItemId: target.id,
    );

    _clearFailedPendingLoad(pending);
    _publishFailure(
      error,
      context: context,
      itemId: target.id,
      retryContext: retry,
    );
  }

  void _clearFailedPendingLoad(PendingLoadContext pending) {
    if (!identical(_pending, pending)) {
      return;
    }

    _pending = null;
    _pendingEffectiveSequence = null;
    _pendingEffectiveSequenceGeneration = null;
    _pendingEffectiveSequenceEpoch = null;
    _pendingShuffleCandidate = null;
    _invalidateSpeedFlightForGeneration(pending.generation);
    _invalidateRepeatFlightForGeneration(pending.generation);
    _invalidateShuffleFlightForGeneration(pending.generation);
  }

  void _publishFailure(
    Object error, {
    required PlayerFailureContext context,
    required String itemId,
    required RetryContext retryContext,
  }) {
    final failure = _failureMapper.map(
      error,
      context: context,
      platform: _failurePlatformResolver(),
      itemId: itemId,
    );
    if (failure == null) {
      return;
    }

    _retryContext = failure.isRecoverable ? retryContext : null;
    _reduceAndPublish(
      () =>
          _snapshotReducer.onFailure(failure, preserveConfirmedPlaying: false),
    );
  }

  void _startAutoplay(LoadGeneration generation) {
    if (_disposed || !_commandCoordinator.isCurrent(generation)) {
      return;
    }

    final playFuture = _requestDesiredPlaying(
      true,
      platformCall: (_) => _engine.play(),
    );
    unawaited(
      playFuture.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          _publishPausedAfterAutoplayFailure(generation);
        },
      ),
    );
  }

  void _publishPausedAfterAutoplayFailure(LoadGeneration generation) {
    if (_disposed || !_commandCoordinator.isCurrent(generation)) {
      return;
    }

    final paused = _snapshotReducer.onPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    _routeImmediate(paused);
  }

  Future<void> _interruptCurrentLoad() async {
    final flight = _activeLoad;
    if (flight == null) {
      return;
    }

    try {
      await _engine.interruptLoad();
    } finally {
      flight.completeInterrupt();
      _invalidateSpeedFlightForGeneration(flight.generation);
      _invalidateRepeatFlightForGeneration(flight.generation);
      _invalidateShuffleFlightForGeneration(flight.generation);
    }
  }

  @override
  Future<void> handlePlay(CommandSource source) {
    _notifyCommandObserver('play', source);

    final pending = _currentPendingLoad();
    if (pending != null) {
      pending.desiredPlaying = true;
      return Future<void>.value();
    }

    final snapshot = _latestSnapshot;
    final currentItem = snapshot.currentItem;
    final currentIndex = snapshot.currentIndex;
    if (snapshot.failure != null ||
        snapshot.processingState == PlaybackProcessingState.error) {
      return _commandNotReady('play', source, notify: false);
    }

    if (currentItem == null || currentIndex == null) {
      return _commandNoCurrentItem('play', source, notify: false);
    }

    final currentIntent = _playPauseIntent;
    if (snapshot.isCompleted) {
      if (currentIntent != null &&
          currentIntent.desired &&
          currentIntent.operation != null &&
          _isCurrentPlayPauseIntent(currentIntent)) {
        return currentIntent.operation!;
      }

      return _requestDesiredPlaying(
        true,
        platformCall: (intent) => _runReplay(
          intent,
          item: currentItem,
          index: currentIndex,
          logicalIndex: _toLogicalEngineIndex(
            effectiveIndex: currentIndex,
            item: currentItem,
          ),
        ),
      );
    }

    if (snapshot.playing && (currentIntent == null || currentIntent.desired)) {
      return Future<void>.value();
    }

    return _requestDesiredPlaying(true, platformCall: (_) => _engine.play());
  }

  Future<void> _runReplay(
    _PlayPauseIntent intent, {
    required PlayerItem item,
    required int index,
    required int logicalIndex,
  }) async {
    await _engine.seek(Duration.zero, index: logicalIndex);
    if (!_isCurrentReplayContinuation(intent, item: item, index: index)) {
      return;
    }

    await _engine.play();
  }

  bool _isCurrentReplayContinuation(
    _PlayPauseIntent intent, {
    required PlayerItem item,
    required int index,
  }) {
    if (_disposed) {
      return false;
    }

    if (_latestSnapshot.currentIndex != index ||
        _latestSnapshot.currentItem != item) {
      return false;
    }

    if (_isCurrentPlayPauseIntent(intent)) {
      return true;
    }

    // The coordinator may hand the same in-flight Play operation back after
    // an opposite pending intent is superseded. Preserve the stale guard, but
    // let the original seek continue when the current record owns that exact
    // operation and source.
    final current = _playPauseIntent;
    return current != null &&
        current.desired &&
        intent.desired &&
        current.operation != null &&
        identical(current.operation, intent.operation) &&
        _commandCoordinator.isSourceTokenCurrent(intent.sourceToken) &&
        _commandCoordinator.isSourceTokenCurrent(current.sourceToken);
  }

  Future<void> _requestDesiredPlaying(
    bool desired, {
    required Future<void> Function(_PlayPauseIntent intent) platformCall,
  }) {
    final existing = _playPauseIntent;
    _PlayPauseIntent intent;
    if (existing != null &&
        existing.desired == desired &&
        existing.operation != null &&
        _isCurrentPlayPauseIntent(existing)) {
      return existing.operation!;
    }

    intent = _PlayPauseIntent(
      desired: desired,
      sequence: ++_nextPlayPauseSequence,
      sourceToken: _commandCoordinator.captureSourceToken(),
    );
    _playPauseIntent = intent;
    _setActiveDesiredPlaying(desired);

    final operation = _commandCoordinator.setDesiredPlaying(desired, () {
      intent.dispatched = true;
      if (!_isCurrentPlayPauseIntent(intent)) {
        return Future<void>.value();
      }
      return platformCall(intent);
    });
    intent.operation = operation;
    intent.dispatched = _commandCoordinator.isPlayPauseOperationDispatched(
      operation,
    );
    unawaited(
      operation.then<void>(
        // A successful platform Future only means that the engine command
        // completed. The confirmed state still comes from playerStateStream.
        (_) {},
        onError: (Object _, StackTrace _) => _failPlayPauseIntent(intent),
      ),
    );
    return operation;
  }

  bool _isCurrentPlayPauseIntent(_PlayPauseIntent intent) =>
      !_disposed &&
      identical(_playPauseIntent, intent) &&
      _commandCoordinator.isSourceTokenCurrent(intent.sourceToken);

  void _reconcilePlayPauseConfirmation(bool playing) {
    final intent = _playPauseIntent;
    if (intent == null ||
        !intent.dispatched ||
        intent.desired != playing ||
        !_isCurrentPlayPauseIntent(intent)) {
      return;
    }

    _playPauseIntent = null;
  }

  void _failPlayPauseIntent(_PlayPauseIntent intent) {
    if (!_isCurrentPlayPauseIntent(intent)) {
      return;
    }

    _playPauseIntent = null;
    _setActiveDesiredPlaying(_latestSnapshot.playing);
  }

  @override
  Future<void> handlePause(CommandSource source) {
    _notifyCommandObserver('pause', source);

    final pending = _currentPendingLoad();
    if (pending != null) {
      pending.desiredPlaying = false;
      _playPauseIntent = null;
      return Future<void>.value();
    }

    final snapshot = _latestSnapshot;
    if (snapshot.failure != null ||
        snapshot.processingState == PlaybackProcessingState.error ||
        snapshot.currentItem == null ||
        snapshot.currentIndex == null) {
      _playPauseIntent = null;
      return Future<void>.value();
    }

    final currentIntent = _playPauseIntent;
    if (!snapshot.playing) {
      if (currentIntent != null &&
          !currentIntent.desired &&
          currentIntent.operation != null &&
          _isCurrentPlayPauseIntent(currentIntent)) {
        return currentIntent.operation!;
      }
      if (currentIntent == null || !currentIntent.desired) {
        return Future<void>.value();
      }
    }

    return _requestDesiredPlaying(false, platformCall: (_) => _engine.pause());
  }

  @override
  Future<void> handleStop(CommandSource source) =>
      _commandNotReady('stop', source);

  @override
  Future<void> handleSeek(Duration position, CommandSource source) => _runSeek(
    command: 'seek',
    source: source,
    resolveTarget: (snapshot) => PlaybackPositionPolicy.clampSeek(
      target: position,
      duration: snapshot.duration,
    ),
  );

  @override
  Future<void> handleSkipBy(Duration offset, CommandSource source) => _runSeek(
    command: 'skipBy',
    source: source,
    resolveTarget: (snapshot) => PlaybackPositionPolicy.skipTarget(
      position: snapshot.position,
      offset: offset,
      duration: snapshot.duration,
    ),
  );

  @override
  Future<void> rewind() => handleSkipBy(
    -PlayerCommandPolicies.skipInterval,
    CommandSource.systemRemote,
  );

  @override
  Future<void> fastForward() => handleSkipBy(
    PlayerCommandPolicies.skipInterval,
    CommandSource.systemRemote,
  );

  Future<void> _runSeek({
    required String command,
    required CommandSource source,
    required Duration? Function(PlaybackSnapshot snapshot) resolveTarget,
  }) {
    _notifyCommandObserver(command, source);

    // The reducer is the latest engine-confirmed accumulator. The UI-facing
    // snapshot may intentionally lag behind it while position cadence is
    // pending.
    final snapshot = _snapshotReducer.latest;
    if (_pending != null ||
        snapshot.processingState == PlaybackProcessingState.loading ||
        snapshot.processingState == PlaybackProcessingState.error ||
        snapshot.failure != null) {
      return _commandNotReady(command, source, notify: false);
    }

    if (snapshot.currentItem == null) {
      return _commandNoCurrentItem(command, source, notify: false);
    }

    final target = resolveTarget(snapshot);
    if (target == null) {
      return _commandSeekUnavailable(command, source, notify: false);
    }

    final confirmation = _SeekConfirmation(
      sequence: ++_nextSeekConfirmationSequence,
      target: target,
      sourceToken: _commandCoordinator.captureSourceToken(),
    );
    _pendingSeekConfirmation = confirmation;
    return _seekEngineTarget(confirmation);
  }

  Future<void> _seekEngineTarget(_SeekConfirmation confirmation) async {
    try {
      await _engine.seek(confirmation.target);
    } catch (error, stackTrace) {
      if (identical(_pendingSeekConfirmation, confirmation)) {
        _pendingSeekConfirmation = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> handleNext(CommandSource source) =>
      _runNavigation(command: 'next', source: source, next: true);

  @override
  Future<void> handlePrevious(CommandSource source) =>
      _runNavigation(command: 'previous', source: source, next: false);

  void _prepareNavigation() {
    _playPauseIntent = null;
    _pendingSeekConfirmation = null;
    _invalidateActiveShuffleFlight();
  }

  int _activeLogicalIndex(
    ActivePlaybackContext active,
    PlaybackSnapshot snapshot,
  ) {
    final effectiveIndex = snapshot.currentIndex;
    if (effectiveIndex == null ||
        effectiveIndex < 0 ||
        effectiveIndex >= active.effectiveQueue.length) {
      throw StateError(
        'Cannot restore an active graph without a current item.',
      );
    }

    final currentItem = active.effectiveQueue[effectiveIndex];
    final logicalIndex = active.logicalQueue.indexOf(currentItem);
    if (logicalIndex < 0) {
      throw StateError(
        'The active effective queue is not backed by its graph.',
      );
    }
    return logicalIndex;
  }

  Future<_RestoredGraph?> _restoreActiveGraph(
    ActivePlaybackContext active,
    PlaybackSnapshot snapshot,
    PlaybackSourceToken sourceToken,
  ) async {
    final logicalIndex = _activeLogicalIndex(active, snapshot);
    final sources = active.logicalQueue
        .map(PlayerItemMapper.toAudioSource)
        .toList(growable: false);
    final restoring = _RestoreGraphContext(sourceToken);
    final flight = _LoadFlight();
    _restoring = restoring;
    _activeLoad = flight;

    try {
      // A replacement load has already changed the platform graph. Restore the
      // last committed graph before any navigation index is sent to the engine.
      final engineLoad = _engine.load(sources, initialIndex: logicalIndex);
      unawaited(
        engineLoad.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      try {
        await Future.any<void>([engineLoad, flight.interrupted]);
      } catch (error, stackTrace) {
        if (flight.wasInterrupted ||
            !_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
          return null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (flight.wasInterrupted ||
          !_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
        return null;
      }

      final engineSeek = _engine.seek(snapshot.position, index: logicalIndex);
      try {
        await Future.any<void>([engineSeek, flight.interrupted]);
      } catch (error, stackTrace) {
        if (flight.wasInterrupted ||
            !_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
          return null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (flight.wasInterrupted ||
          !_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
        return null;
      }

      if (restoring.effectiveSequence == null) {
        await Future.any<void>([
          restoring.effectiveSequenceFuture.then<void>((_) {}),
          flight.interrupted,
        ]);
      }
      if (flight.wasInterrupted ||
          !_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
        return null;
      }

      final sequence = _validEffectiveSequence(
        restoring.effectiveSequence,
        active.logicalQueue.length,
      );
      if (sequence == null) {
        return null;
      }

      final effectiveQueue = _effectiveQueue(active.logicalQueue, sequence);
      if (effectiveQueue == null) {
        return null;
      }

      final currentIndex = _toEffectiveIndex(
        logicalIndex,
        sequence: sequence,
        queueLength: active.logicalQueue.length,
      );
      if (currentIndex == null) {
        return null;
      }
      return _RestoredGraph(
        effectiveQueue: effectiveQueue,
        effectiveSequence: sequence,
        currentIndex: currentIndex,
      );
    } finally {
      if (identical(_activeLoad, flight)) {
        _activeLoad = null;
      }
      if (identical(_restoring, restoring)) {
        _restoring = null;
      }
    }
  }

  void _publishRestoredActiveState(
    ActivePlaybackContext active,
    PlaybackSnapshot snapshot,
    int currentIndex,
  ) {
    _snapshotReducer.commitQueue(
      active.effectiveQueue,
      currentIndex: currentIndex,
    );
    _snapshotReducer.onPosition(snapshot.position);
    final ready = _snapshotReducer.onPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    _routeImmediate(ready);
  }

  void _resumeRestoredPlayback(
    ActivePlaybackContext active,
    PlaybackSourceToken sourceToken,
  ) {
    if (!active.desiredPlaying) {
      return;
    }

    final play = _requestDesiredPlaying(
      true,
      platformCall: (_) => _engine.play(),
    );
    unawaited(
      play.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (!_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
            return;
          }
          final paused = _snapshotReducer.onPlayerState(
            just_audio.PlayerState(false, just_audio.ProcessingState.ready),
          );
          _routeImmediate(paused);
        },
      ),
    );
  }

  void _clearPendingNavigationContext(PendingLoadContext? expected) {
    if (expected == null || !identical(_pending, expected)) {
      return;
    }

    _pending = null;
    _pendingEffectiveSequence = null;
    _pendingEffectiveSequenceGeneration = null;
    _pendingEffectiveSequenceEpoch = null;
  }

  Future<void> _runNavigationTransaction({
    required PlaybackSnapshot snapshot,
    required ActivePlaybackContext? active,
    required PendingLoadContext? pending,
    required bool restartCurrent,
    required int? logicalIndex,
    required PlaybackSourceToken sourceToken,
  }) async {
    if (!_commandCoordinator.isSourceTokenCurrent(sourceToken) ||
        !identical(_pending, pending)) {
      return;
    }

    ActivePlaybackContext? restoredActive;
    if (pending != null) {
      final committedActive = active;
      if (committedActive == null) {
        return;
      }

      final restored = await _restoreActiveGraph(
        committedActive,
        snapshot,
        sourceToken,
      );
      if (restored == null ||
          !_commandCoordinator.isSourceTokenCurrent(sourceToken) ||
          !identical(_pending, pending)) {
        return;
      }

      _effectiveSequence = restored.effectiveSequence;
      restoredActive = ActivePlaybackContext(
        logicalQueue: committedActive.logicalQueue,
        effectiveQueue: restored.effectiveQueue,
        currentIndex: restored.currentIndex,
        position: snapshot.position,
        desiredPlaying: committedActive.desiredPlaying,
      );
      _active = restoredActive;
      _publishRestoredActiveState(
        restoredActive,
        snapshot,
        restored.currentIndex,
      );
      // The pending context has absorbed the interrupt and restore events.
      // Clear it only after the committed graph is back and immediately
      // before the optional navigation seek.
      _clearPendingNavigationContext(pending);
    }

    if (!_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
      return;
    }
    if (!restartCurrent && logicalIndex != null) {
      await _engine.seek(Duration.zero, index: logicalIndex);
    } else if (restartCurrent) {
      await _engine.seek(Duration.zero);
    }

    if (!_commandCoordinator.isSourceTokenCurrent(sourceToken)) {
      return;
    }
    if (restoredActive != null) {
      _resumeRestoredPlayback(restoredActive, sourceToken);
    }
  }

  Future<void> _runNavigation({
    required String command,
    required CommandSource source,
    required bool next,
  }) {
    _notifyCommandObserver(command, source);

    final snapshot = _snapshotReducer.latest;
    final active = _active;
    final pending = _pending;
    if (snapshot.failure != null ||
        snapshot.processingState == PlaybackProcessingState.error) {
      return _commandNotReady(command, source, notify: false);
    }
    if (pending != null && active == null) {
      return _commandNotReady(command, source, notify: false);
    }
    if (pending == null &&
        snapshot.processingState == PlaybackProcessingState.loading) {
      return _commandNotReady(command, source, notify: false);
    }

    final effectiveQueue = pending != null
        ? active!.effectiveQueue
        : snapshot.queue;
    final currentIndex = snapshot.currentIndex;
    if (snapshot.currentItem == null ||
        currentIndex == null ||
        currentIndex < 0 ||
        currentIndex >= effectiveQueue.length) {
      return _commandNoCurrentItem(command, source, notify: false);
    }

    final logicalQueue = active?.logicalQueue ?? effectiveQueue;
    final sequence =
        _validEffectiveSequence(_effectiveSequence, logicalQueue.length) ??
        _identitySequence(logicalQueue.length);

    int? targetIndex;
    var restartCurrent = false;
    if (next) {
      if (currentIndex < effectiveQueue.length - 1) {
        targetIndex = currentIndex + 1;
      } else if (snapshot.repeatMode == PlayerRepeatMode.all) {
        targetIndex = 0;
      }
    } else {
      final decision = PlaybackPositionPolicy.previous(
        position: snapshot.position,
        currentIndex: currentIndex,
        queueLength: effectiveQueue.length,
      );
      switch (decision.kind) {
        case PreviousDecisionKind.restartCurrent:
          restartCurrent = true;
        case PreviousDecisionKind.navigateToIndex:
          targetIndex = decision.targetIndex;
        case PreviousDecisionKind.noOp:
          if (snapshot.repeatMode == PlayerRepeatMode.all &&
              currentIndex == 0) {
            targetIndex = effectiveQueue.length - 1;
          }
      }
    }

    if (!restartCurrent && targetIndex == null) {
      if (pending == null) {
        return Future<void>.value();
      }
    }
    if (!restartCurrent &&
        targetIndex != null &&
        (targetIndex < 0 || targetIndex >= effectiveQueue.length)) {
      if (pending == null) {
        return Future<void>.value();
      }
    }

    _prepareNavigation();
    final sourceToken = _commandCoordinator.beginSourceNavigation();

    final logicalIndex = restartCurrent || targetIndex == null
        ? null
        : sequence[targetIndex];
    return _commandCoordinator.switchSourceIndex(
      () => _runNavigationTransaction(
        snapshot: snapshot,
        active: active,
        pending: pending,
        restartCurrent: restartCurrent,
        logicalIndex: logicalIndex,
        sourceToken: sourceToken,
      ),
      interrupt: _interruptCurrentLoad,
      sourceToken: sourceToken,
    );
  }

  Future<void> _preparePendingSpeed(
    PendingLoadContext pending,
    _LoadFlight loadFlight,
  ) async {
    if (_desiredSpeedRevision == 0) {
      return;
    }

    while (!_disposed &&
        identical(_pending, pending) &&
        _commandCoordinator.isCurrent(pending.generation)) {
      final desiredSpeed = _desiredSpeed;
      final desiredRevision = _desiredSpeedRevision;
      if (_lastAppliedSpeedGeneration == pending.generation &&
          _lastAppliedSpeedRevision == desiredRevision &&
          _lastConfirmedSpeed == desiredSpeed) {
        return;
      }

      final flight = _enqueueSpeedFlight(
        speed: desiredSpeed,
        revision: desiredRevision,
        generation: pending.generation,
      );
      try {
        await Future.any<void>([flight.future, loadFlight.interrupted]);
      } catch (_) {
        if (desiredRevision != _desiredSpeedRevision ||
            desiredSpeed != _desiredSpeed) {
          continue;
        }
        rethrow;
      }
      if (loadFlight.wasInterrupted) {
        return;
      }

      if (!flight.confirmed) {
        await Future.any<void>([
          flight.confirmation.future,
          loadFlight.interrupted,
        ]);
        if (loadFlight.wasInterrupted) {
          return;
        }
      }

      if (desiredRevision == _desiredSpeedRevision &&
          desiredSpeed == _desiredSpeed &&
          _lastAppliedSpeedGeneration == pending.generation &&
          _lastAppliedSpeedRevision == desiredRevision &&
          _lastConfirmedSpeed == desiredSpeed) {
        return;
      }
    }
  }

  Future<void> _preparePendingRepeat(
    PendingLoadContext pending,
    _LoadFlight loadFlight,
  ) async {
    if (_desiredRepeatRevision == 0) {
      return;
    }

    while (!_disposed &&
        identical(_pending, pending) &&
        _commandCoordinator.isCurrent(pending.generation)) {
      final desiredMode = _desiredRepeatMode;
      final desiredRevision = _desiredRepeatRevision;
      if (_lastAppliedRepeatGeneration == pending.generation &&
          _lastAppliedRepeatRevision == desiredRevision &&
          _lastConfirmedRepeatMode == desiredMode) {
        return;
      }

      final flight = _enqueueRepeatFlight(
        mode: desiredMode,
        revision: desiredRevision,
        generation: pending.generation,
      );
      try {
        await Future.any<void>([flight.future, loadFlight.interrupted]);
      } catch (_) {
        if (desiredRevision != _desiredRepeatRevision ||
            desiredMode != _desiredRepeatMode) {
          continue;
        }
        rethrow;
      }
      if (loadFlight.wasInterrupted) {
        return;
      }

      if (!flight.confirmed) {
        await Future.any<void>([
          flight.confirmation.future,
          loadFlight.interrupted,
        ]);
        if (loadFlight.wasInterrupted) {
          return;
        }
      }

      if (desiredRevision == _desiredRepeatRevision &&
          desiredMode == _desiredRepeatMode &&
          _lastAppliedRepeatGeneration == pending.generation &&
          _lastAppliedRepeatRevision == desiredRevision &&
          _lastConfirmedRepeatMode == desiredMode) {
        return;
      }
    }
  }

  Future<void> _preparePendingShuffle(
    PendingLoadContext pending,
    _LoadFlight loadFlight,
  ) async {
    if (_desiredShuffleRevision == 0) {
      return;
    }

    while (!_disposed &&
        identical(_pending, pending) &&
        _commandCoordinator.isCurrent(pending.generation)) {
      final desiredEnabled = _desiredShuffleEnabled;
      final desiredRevision = _desiredShuffleRevision;
      final prepared = _pendingShuffleCandidate;
      if (_lastConfirmedShuffleEnabled == desiredEnabled &&
          _isPendingShuffleCandidateValid(
            prepared,
            pending,
            prepared?.sequence,
          ) &&
          prepared?.revision == desiredRevision) {
        return;
      }

      final flight = _enqueueShuffleFlight(
        enabled: desiredEnabled,
        revision: desiredRevision,
        generation: pending.generation,
        anchorItem: _latestSnapshot.currentItem,
      );
      try {
        await Future.any<void>([flight.future, loadFlight.interrupted]);
      } catch (_) {
        if (desiredRevision != _desiredShuffleRevision ||
            desiredEnabled != _desiredShuffleEnabled) {
          continue;
        }
        rethrow;
      }
      if (loadFlight.wasInterrupted) {
        return;
      }

      if (!flight.modeConfirmed) {
        await Future.any<void>([
          flight.modeConfirmation.future,
          loadFlight.interrupted,
        ]);
        if (loadFlight.wasInterrupted) {
          return;
        }
      }

      if (flight.sequenceCandidate == null) {
        await Future.any<void>([
          flight.sequenceConfirmation.future,
          loadFlight.interrupted,
        ]);
        if (loadFlight.wasInterrupted) {
          return;
        }
      }

      final candidate = flight.sequenceCandidate;
      if (desiredRevision == _desiredShuffleRevision &&
          desiredEnabled == _desiredShuffleEnabled &&
          flight.modeConfirmed &&
          _lastConfirmedShuffleEnabled == desiredEnabled &&
          _isPendingShuffleCandidateValid(
            candidate,
            pending,
            candidate?.sequence,
          ) &&
          _isShuffleCandidateAfterDispatch(candidate, flight)) {
        _pendingShuffleCandidate = candidate;
        return;
      }
    }
  }

  List<int>? _committedShuffleSequence(PendingLoadContext pending) {
    if (_desiredShuffleRevision == 0) {
      return null;
    }

    final candidate = _pendingShuffleCandidate;
    if (!_isPendingShuffleCandidateValid(
          candidate,
          pending,
          candidate?.sequence,
        ) ||
        !_isShuffleCandidateAfterDispatch(candidate, _shuffleFlight)) {
      return null;
    }
    return candidate!.sequence;
  }

  bool _isPendingShuffleCandidateValid(
    _ShuffleSequenceCandidate? candidate,
    PendingLoadContext pending,
    List<int>? sequence,
  ) {
    if (candidate == null ||
        sequence == null ||
        candidate.generation != pending.generation ||
        candidate.revision != _desiredShuffleRevision ||
        !_isShuffleCandidateAfterDispatch(candidate, _shuffleFlight) ||
        !_isShuffleSequenceValid(
          sequence,
          queueLength: pending.targetQueue.length,
          enabled: _desiredShuffleEnabled,
        )) {
      return false;
    }
    return true;
  }

  bool _isShuffleCandidateAfterDispatch(
    _ShuffleSequenceCandidate? candidate,
    _ShuffleFlight? flight,
  ) {
    return candidate != null &&
        flight != null &&
        candidate.eventEpoch > flight.sequenceEpochAtDispatch;
  }

  bool _isShuffleSequenceValid(
    Iterable<int> sequence, {
    required int queueLength,
    required bool enabled,
  }) {
    final indexes = _validEffectiveSequence(sequence, queueLength);
    if (indexes == null) {
      return false;
    }
    if (enabled) {
      return true;
    }
    return indexes.length == _identitySequence(queueLength).length &&
        indexes.every((index) => index == indexes.indexOf(index));
  }

  void _tryCommitShuffleFlight(_ShuffleFlight flight) {
    if (_disposed ||
        !identical(_shuffleFlight, flight) ||
        flight.superseded ||
        flight.committed ||
        !flight.modeConfirmed ||
        flight.sequenceCandidate == null ||
        flight.revision != _desiredShuffleRevision ||
        flight.enabled != _desiredShuffleEnabled) {
      return;
    }

    final pending = _currentPendingLoad();
    if (pending != null) {
      if (flight.generation != pending.generation) {
        return;
      }
      return;
    }
    if (flight.generation != null) {
      return;
    }

    final active = _active;
    final logicalQueue = active?.logicalQueue ?? _snapshotReducer.latest.queue;
    final candidate = flight.sequenceCandidate!;
    if (!_isShuffleSequenceValid(
      candidate.sequence,
      queueLength: logicalQueue.length,
      enabled: flight.enabled,
    )) {
      return;
    }

    final effectiveQueue = _effectiveQueue(logicalQueue, candidate.sequence);
    if (effectiveQueue == null) {
      return;
    }

    final anchorItem = flight.anchorItem ?? _snapshotReducer.latest.currentItem;
    final logicalIndex = anchorItem == null
        ? null
        : logicalQueue.indexOf(anchorItem);
    final effectiveIndex = _toEffectiveIndex(
      logicalIndex,
      sequence: candidate.sequence,
      queueLength: logicalQueue.length,
    );

    _snapshotReducer.onShuffleEnabled(flight.enabled);
    final committed = _snapshotReducer.commitQueue(
      effectiveQueue,
      currentIndex: effectiveIndex,
    );
    _effectiveSequence = candidate.sequence;
    _updateActiveQueue(effectiveQueue, committed.currentIndex);
    flight.committed = true;
    _routeImmediate(committed);
    _maybeFinalizeShuffleFlight(flight);
  }

  _ShuffleFlight _enqueueShuffleFlight({
    required bool enabled,
    required int revision,
    required LoadGeneration? generation,
    required PlayerItem? anchorItem,
  }) {
    final current = _shuffleFlight;
    if (current != null &&
        current.enabled == enabled &&
        current.revision == revision &&
        current.generation == generation) {
      return current;
    }
    if (current == null) {
      final flight = _ShuffleFlight(
        enabled: enabled,
        revision: revision,
        generation: generation,
        anchorItem: anchorItem,
        sequenceEpochAtDispatch: _effectiveSequenceEpoch,
      );
      _shuffleFlight = flight;
      _dispatchShuffleFlight(flight);
      return flight;
    }

    final queued = _queuedShuffleFlight;
    if (queued != null &&
        queued.enabled == enabled &&
        queued.generation == generation) {
      return queued;
    }

    if (queued != null) {
      _supersedeShuffleFlight(queued);
    }

    final next = _ShuffleFlight(
      enabled: enabled,
      revision: revision,
      generation: generation,
      anchorItem: anchorItem,
      sequenceEpochAtDispatch: _effectiveSequenceEpoch,
    );
    _queuedShuffleFlight = next;
    if (current.platformCompleted) {
      _dispatchQueuedShuffleFlight();
    }
    return next;
  }

  void _dispatchShuffleFlight(_ShuffleFlight flight) {
    if (_disposed || flight.dispatched || flight.superseded) {
      return;
    }

    flight.dispatched = true;
    flight.sequenceEpochAtDispatch = _effectiveSequenceEpoch;
    if (flight.generation != null &&
        _pending?.generation == flight.generation) {
      _pendingEffectiveSequence = null;
      _pendingEffectiveSequenceGeneration = null;
      _pendingEffectiveSequenceEpoch = null;
    }
    Future<void> operation;
    try {
      operation = _engine.setShuffleEnabled(flight.enabled);
    } catch (error, stackTrace) {
      _finishShuffleFlightWithError(flight, error, stackTrace);
      return;
    }

    unawaited(
      operation.then<void>(
        (_) => _finishShuffleFlight(flight),
        onError: (Object error, StackTrace stackTrace) {
          _finishShuffleFlightWithError(flight, error, stackTrace);
        },
      ),
    );
  }

  void _dispatchQueuedShuffleFlight() {
    final current = _shuffleFlight;
    final queued = _queuedShuffleFlight;
    if (current == null || queued == null || !current.platformCompleted) {
      return;
    }

    _queuedShuffleFlight = null;
    _shuffleFlight = queued;
    _dispatchShuffleFlight(queued);
  }

  void _finishShuffleFlight(_ShuffleFlight flight) {
    flight.platformCompleted = true;
    flight.completeSuccess();

    if (!identical(_shuffleFlight, flight)) {
      return;
    }

    if (_queuedShuffleFlight != null) {
      if (!flight.modeConfirmation.isCompleted) {
        flight.modeConfirmation.complete();
      }
      if (!flight.sequenceConfirmation.isCompleted) {
        flight.sequenceConfirmation.complete();
      }
      _dispatchQueuedShuffleFlight();
      return;
    }
    _maybeFinalizeShuffleFlight(flight);
  }

  void _finishShuffleFlightWithError(
    _ShuffleFlight flight,
    Object error,
    StackTrace stackTrace,
  ) {
    flight.platformCompleted = true;
    flight.modeConfirmed = false;
    flight.sequenceCandidate = null;
    if (_pending?.generation == flight.generation) {
      _pendingShuffleCandidate = null;
    }
    flight.completeError(error, stackTrace);

    if (!identical(_shuffleFlight, flight)) {
      return;
    }

    if (_queuedShuffleFlight != null) {
      if (!flight.modeConfirmation.isCompleted) {
        flight.modeConfirmation.complete();
      }
      if (!flight.sequenceConfirmation.isCompleted) {
        flight.sequenceConfirmation.complete();
      }
      _dispatchQueuedShuffleFlight();
      return;
    }

    _shuffleFlight = null;
    if (_desiredShuffleRevision == flight.revision &&
        _desiredShuffleEnabled == flight.enabled) {
      _desiredShuffleEnabled = _lastConfirmedShuffleEnabled;
      _desiredShuffleRevision++;
    }
  }

  void _maybeFinalizeShuffleFlight(_ShuffleFlight? flight) {
    if (flight == null || !identical(_shuffleFlight, flight)) {
      return;
    }
    if (flight.generation != null && _pending != null) {
      return;
    }
    if (flight.platformCompleted &&
        flight.committed &&
        _queuedShuffleFlight == null) {
      _shuffleFlight = null;
    }
  }

  void _invalidateActiveShuffleFlight() {
    final current = _shuffleFlight;
    if (current == null || current.generation != null) {
      return;
    }
    _supersedeShuffleFlight(current);
    _shuffleFlight = null;
    final queued = _queuedShuffleFlight;
    if (queued != null && queued.generation == null) {
      _supersedeShuffleFlight(queued);
      _queuedShuffleFlight = null;
    }
  }

  void _invalidateShuffleFlightForGeneration(LoadGeneration? generation) {
    if (generation == null) {
      return;
    }

    final current = _shuffleFlight;
    if (current != null && current.generation == generation) {
      _supersedeShuffleFlight(current);
      _shuffleFlight = null;
      final queued = _queuedShuffleFlight;
      if (queued != null) {
        _supersedeShuffleFlight(queued);
        _queuedShuffleFlight = null;
      }
      _pendingShuffleCandidate = null;
      if (_pending?.generation == generation) {
        _pendingEffectiveSequence = null;
        _pendingEffectiveSequenceGeneration = null;
        _pendingEffectiveSequenceEpoch = null;
      }
      return;
    }

    final queued = _queuedShuffleFlight;
    if (queued != null && queued.generation == generation) {
      _supersedeShuffleFlight(queued);
      _queuedShuffleFlight = null;
      if (_pending?.generation == generation) {
        _pendingEffectiveSequence = null;
        _pendingEffectiveSequenceGeneration = null;
        _pendingEffectiveSequenceEpoch = null;
      }
    }
  }

  void _supersedeShuffleFlight(_ShuffleFlight flight) {
    flight.superseded = true;
    flight.modeConfirmed = false;
    flight.sequenceCandidate = null;
    flight.completeSuccess();
    if (!flight.modeConfirmation.isCompleted) {
      flight.modeConfirmation.complete();
    }
    if (!flight.sequenceConfirmation.isCompleted) {
      flight.sequenceConfirmation.complete();
    }
  }

  Future<void> _submitShuffle(bool enabled, {LoadGeneration? generation}) {
    final existing = _matchingShuffleFlight(enabled, generation);
    if (existing != null &&
        existing.revision == _desiredShuffleRevision &&
        _desiredShuffleEnabled == enabled) {
      return existing.future;
    }

    _desiredShuffleEnabled = enabled;
    final revision = ++_desiredShuffleRevision;
    return _enqueueShuffleFlight(
      enabled: enabled,
      revision: revision,
      generation: generation,
      anchorItem: _latestSnapshot.currentItem,
    ).future;
  }

  _ShuffleFlight? _matchingShuffleFlight(
    bool enabled,
    LoadGeneration? generation,
  ) {
    final current = _shuffleFlight;
    if (current != null &&
        current.enabled == enabled &&
        current.generation == generation) {
      return current;
    }

    final queued = _queuedShuffleFlight;
    if (queued != null &&
        queued.enabled == enabled &&
        queued.generation == generation) {
      return queued;
    }
    return null;
  }

  Future<void> _submitSpeed(double speed, {LoadGeneration? generation}) {
    final existing = _matchingSpeedFlight(speed, generation);
    if (existing != null &&
        existing.revision == _desiredSpeedRevision &&
        _desiredSpeed == speed) {
      return existing.future;
    }

    _desiredSpeed = speed;
    final revision = ++_desiredSpeedRevision;
    return _enqueueSpeedFlight(
      speed: speed,
      revision: revision,
      generation: generation,
    ).future;
  }

  _SpeedFlight? _matchingSpeedFlight(double speed, LoadGeneration? generation) {
    final current = _speedFlight;
    if (current != null &&
        current.speed == speed &&
        current.generation == generation) {
      return current;
    }

    final queued = _queuedSpeedFlight;
    if (queued != null &&
        queued.speed == speed &&
        queued.generation == generation) {
      return queued;
    }
    return null;
  }

  _SpeedFlight _enqueueSpeedFlight({
    required double speed,
    required int revision,
    required LoadGeneration? generation,
  }) {
    final current = _speedFlight;
    if (current == null) {
      final flight = _SpeedFlight(
        speed: speed,
        revision: revision,
        generation: generation,
      );
      _speedFlight = flight;
      _dispatchSpeedFlight(flight);
      return flight;
    }

    final queued = _queuedSpeedFlight;
    if (queued != null &&
        queued.speed == speed &&
        queued.generation == generation) {
      return queued;
    }

    if (queued != null) {
      _supersedeSpeedFlight(queued);
    }

    final next = _SpeedFlight(
      speed: speed,
      revision: revision,
      generation: generation,
    );
    _queuedSpeedFlight = next;
    if (current.platformCompleted) {
      _dispatchQueuedSpeedFlight();
    }
    return next;
  }

  Future<void> _submitRepeat(
    PlayerRepeatMode mode, {
    LoadGeneration? generation,
  }) {
    // The returned Future acknowledges only the engine command. Outward mode
    // remains engine-confirmed through loopModeStream; pending loads additionally
    // wait for that confirmation before commit.
    final existing = _matchingRepeatFlight(mode, generation);
    if (existing != null &&
        existing.revision == _desiredRepeatRevision &&
        _desiredRepeatMode == mode) {
      return existing.future;
    }

    _desiredRepeatMode = mode;
    final revision = ++_desiredRepeatRevision;
    return _enqueueRepeatFlight(
      mode: mode,
      revision: revision,
      generation: generation,
    ).future;
  }

  _RepeatFlight? _matchingRepeatFlight(
    PlayerRepeatMode mode,
    LoadGeneration? generation,
  ) {
    final current = _repeatFlight;
    if (current != null &&
        current.mode == mode &&
        current.generation == generation) {
      return current;
    }

    final queued = _queuedRepeatFlight;
    if (queued != null &&
        queued.mode == mode &&
        queued.generation == generation) {
      return queued;
    }
    return null;
  }

  _RepeatFlight _enqueueRepeatFlight({
    required PlayerRepeatMode mode,
    required int revision,
    required LoadGeneration? generation,
  }) {
    final current = _repeatFlight;
    if (current == null) {
      final flight = _RepeatFlight(
        mode: mode,
        revision: revision,
        generation: generation,
      );
      _repeatFlight = flight;
      _dispatchRepeatFlight(flight);
      return flight;
    }

    final queued = _queuedRepeatFlight;
    if (queued != null &&
        queued.mode == mode &&
        queued.generation == generation) {
      return queued;
    }

    if (queued != null) {
      _supersedeRepeatFlight(queued);
    }

    final next = _RepeatFlight(
      mode: mode,
      revision: revision,
      generation: generation,
    );
    _queuedRepeatFlight = next;
    if (current.platformCompleted) {
      _dispatchQueuedRepeatFlight();
    }
    return next;
  }

  void _invalidateRepeatFlightForGeneration(LoadGeneration? generation) {
    if (generation == null) {
      return;
    }

    final current = _repeatFlight;
    if (current != null && current.generation == generation) {
      _supersedeRepeatFlight(current);
      _repeatFlight = null;

      final queued = _queuedRepeatFlight;
      if (queued != null) {
        _supersedeRepeatFlight(queued);
        _queuedRepeatFlight = null;
      }
      return;
    }

    final queued = _queuedRepeatFlight;
    if (queued != null && queued.generation == generation) {
      _supersedeRepeatFlight(queued);
      _queuedRepeatFlight = null;
    }
  }

  void _supersedeRepeatFlight(_RepeatFlight flight) {
    flight.superseded = true;
    flight.completeSuccess();
    if (!flight.confirmation.isCompleted) {
      flight.confirmation.complete();
    }
  }

  void _dispatchRepeatFlight(_RepeatFlight flight) {
    if (_disposed || flight.dispatched || flight.superseded) {
      return;
    }

    flight.dispatched = true;
    Future<void> operation;
    try {
      operation = _engine.setLoopMode(
        PlaybackMappers.toEngineRepeat(flight.mode),
      );
    } catch (error, stackTrace) {
      _finishRepeatFlightWithError(flight, error, stackTrace);
      return;
    }

    unawaited(
      operation.then<void>(
        (_) => _finishRepeatFlight(flight),
        onError: (Object error, StackTrace stackTrace) {
          _finishRepeatFlightWithError(flight, error, stackTrace);
        },
      ),
    );
  }

  void _dispatchQueuedRepeatFlight() {
    final current = _repeatFlight;
    final queued = _queuedRepeatFlight;
    if (current == null || queued == null || !current.platformCompleted) {
      return;
    }

    _queuedRepeatFlight = null;
    _repeatFlight = queued;
    _dispatchRepeatFlight(queued);
  }

  void _finishRepeatFlight(_RepeatFlight flight) {
    flight.platformCompleted = true;
    flight.completeSuccess();

    if (!identical(_repeatFlight, flight)) {
      return;
    }

    if (_queuedRepeatFlight != null) {
      if (!flight.confirmation.isCompleted) {
        flight.confirmation.complete();
      }
      _dispatchQueuedRepeatFlight();
      return;
    }
    _maybeFinalizeRepeatFlight(flight);
  }

  void _finishRepeatFlightWithError(
    _RepeatFlight flight,
    Object error,
    StackTrace stackTrace,
  ) {
    flight.platformCompleted = true;
    flight.completeError(error, stackTrace);

    if (!identical(_repeatFlight, flight)) {
      return;
    }

    if (_queuedRepeatFlight != null) {
      if (!flight.confirmation.isCompleted) {
        flight.confirmation.complete();
      }
      _dispatchQueuedRepeatFlight();
      return;
    }

    _repeatFlight = null;
    if (_desiredRepeatRevision == flight.revision &&
        _desiredRepeatMode == flight.mode) {
      _desiredRepeatMode = _lastConfirmedRepeatMode;
      _desiredRepeatRevision++;
    }
  }

  void _maybeFinalizeRepeatFlight(_RepeatFlight flight) {
    if (identical(_repeatFlight, flight) &&
        flight.platformCompleted &&
        flight.confirmed &&
        _queuedRepeatFlight == null) {
      _repeatFlight = null;
    }
  }

  void _invalidateSpeedFlightForGeneration(LoadGeneration? generation) {
    if (generation == null) {
      return;
    }

    final current = _speedFlight;
    if (current != null && current.generation == generation) {
      _supersedeSpeedFlight(current);
      _speedFlight = null;

      // A queued operation was created behind the interrupted load. It must
      // not remain detached from the new load's desired-speed preparation.
      final queued = _queuedSpeedFlight;
      if (queued != null) {
        _supersedeSpeedFlight(queued);
        _queuedSpeedFlight = null;
      }
      return;
    }

    final queued = _queuedSpeedFlight;
    if (queued != null && queued.generation == generation) {
      _supersedeSpeedFlight(queued);
      _queuedSpeedFlight = null;
    }
  }

  void _supersedeSpeedFlight(_SpeedFlight flight) {
    flight.superseded = true;
    flight.completeSuccess();
    if (!flight.confirmation.isCompleted) {
      flight.confirmation.complete();
    }
  }

  void _dispatchSpeedFlight(_SpeedFlight flight) {
    if (_disposed || flight.dispatched || flight.superseded) {
      return;
    }

    flight.dispatched = true;
    Future<void> operation;
    try {
      operation = _engine.setSpeed(flight.speed);
    } catch (error, stackTrace) {
      _finishSpeedFlightWithError(flight, error, stackTrace);
      return;
    }

    unawaited(
      operation.then<void>(
        (_) => _finishSpeedFlight(flight),
        onError: (Object error, StackTrace stackTrace) {
          _finishSpeedFlightWithError(flight, error, stackTrace);
        },
      ),
    );
  }

  void _dispatchQueuedSpeedFlight() {
    final current = _speedFlight;
    final queued = _queuedSpeedFlight;
    if (current == null || queued == null || !current.platformCompleted) {
      return;
    }

    _queuedSpeedFlight = null;
    _speedFlight = queued;
    _dispatchSpeedFlight(queued);
  }

  void _finishSpeedFlight(_SpeedFlight flight) {
    flight.platformCompleted = true;
    flight.completeSuccess();

    if (!identical(_speedFlight, flight)) {
      return;
    }

    if (_queuedSpeedFlight != null) {
      if (!flight.confirmation.isCompleted) {
        flight.confirmation.complete();
      }
      _dispatchQueuedSpeedFlight();
      return;
    }
    _maybeFinalizeSpeedFlight(flight);
  }

  void _finishSpeedFlightWithError(
    _SpeedFlight flight,
    Object error,
    StackTrace stackTrace,
  ) {
    flight.platformCompleted = true;
    flight.completeError(error, stackTrace);

    if (!identical(_speedFlight, flight)) {
      return;
    }

    if (_queuedSpeedFlight != null) {
      if (!flight.confirmation.isCompleted) {
        flight.confirmation.complete();
      }
      _dispatchQueuedSpeedFlight();
      return;
    }

    _speedFlight = null;
    if (_desiredSpeedRevision == flight.revision &&
        _desiredSpeed == flight.speed) {
      _desiredSpeed = _lastConfirmedSpeed;
      _desiredSpeedRevision++;
    }
  }

  void _maybeFinalizeSpeedFlight(_SpeedFlight flight) {
    if (identical(_speedFlight, flight) &&
        flight.platformCompleted &&
        flight.confirmed &&
        _queuedSpeedFlight == null) {
      _speedFlight = null;
    }
  }

  @override
  Future<void> handleSetSpeed(double speed, CommandSource source) {
    _notifyCommandObserver('setSpeed', source);

    if (!PlayerCommandPolicies.isSpeedInRange(speed)) {
      return _commandInvalidSpeed('setSpeed', source, notify: false);
    }

    final pending = _currentPendingLoad();
    if (pending != null) {
      return _submitSpeed(speed, generation: pending.generation);
    }

    final snapshot = _latestSnapshot;
    if (snapshot.failure != null ||
        snapshot.processingState == PlaybackProcessingState.error ||
        snapshot.processingState == PlaybackProcessingState.loading) {
      return _commandNotReady('setSpeed', source, notify: false);
    }

    if (snapshot.currentItem == null || snapshot.currentIndex == null) {
      return _commandNoCurrentItem('setSpeed', source, notify: false);
    }

    return _submitSpeed(speed);
  }

  @override
  Future<void> handleSetRepeatMode(
    PlayerRepeatMode mode,
    CommandSource source,
  ) {
    _notifyCommandObserver('setRepeatMode', source);

    final pending = _currentPendingLoad();
    if (pending != null) {
      return _submitRepeat(mode, generation: pending.generation);
    }

    final snapshot = _latestSnapshot;
    if (snapshot.failure != null ||
        snapshot.processingState == PlaybackProcessingState.error ||
        snapshot.processingState == PlaybackProcessingState.loading) {
      return _commandNotReady('setRepeatMode', source, notify: false);
    }

    if (snapshot.currentItem == null || snapshot.currentIndex == null) {
      return _commandNoCurrentItem('setRepeatMode', source, notify: false);
    }

    return _submitRepeat(mode);
  }

  @override
  Future<void> handleSetShuffleEnabled(bool enabled, CommandSource source) {
    _notifyCommandObserver('setShuffleEnabled', source);

    final pending = _currentPendingLoad();
    if (pending != null) {
      return _submitShuffle(enabled, generation: pending.generation);
    }

    final snapshot = _latestSnapshot;
    if (snapshot.failure != null ||
        snapshot.processingState == PlaybackProcessingState.error ||
        snapshot.processingState == PlaybackProcessingState.loading) {
      return _commandNotReady('setShuffleEnabled', source, notify: false);
    }

    if (snapshot.currentItem == null || snapshot.currentIndex == null) {
      return _commandNoCurrentItem('setShuffleEnabled', source, notify: false);
    }

    return _submitShuffle(enabled);
  }

  @override
  Future<void> handleRetry(CommandSource source) =>
      _commandNotReady('retry', source);

  @override
  Future<void> play() => handlePlay(CommandSource.systemRemote);

  @override
  Future<void> pause() => handlePause(CommandSource.systemRemote);

  @override
  Future<void> stop() => handleStop(CommandSource.systemRemote);

  @override
  Future<void> seek(Duration position) =>
      handleSeek(position, CommandSource.systemRemote);

  @override
  Future<void> skipToNext() => handleNext(CommandSource.systemRemote);

  @override
  Future<void> skipToPrevious() => handlePrevious(CommandSource.systemRemote);

  @override
  Future<void> setSpeed(double speed) =>
      handleSetSpeed(speed, CommandSource.systemRemote);

  @override
  Future<void> setRepeatMode(audio_service.AudioServiceRepeatMode repeatMode) =>
      handleSetRepeatMode(
        PlaybackMappers.fromAudioServiceRepeat(repeatMode),
        CommandSource.systemRemote,
      );

  @override
  Future<void> setShuffleMode(
    audio_service.AudioServiceShuffleMode shuffleMode,
  ) => handleSetShuffleEnabled(
    PlaybackMappers.fromAudioServiceShuffle(shuffleMode),
    CommandSource.systemRemote,
  );

  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    final future = _disposeResources();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeResources() async {
    _disposed = true;
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    final projectionSubscriptions =
        List<StreamSubscription<PlaybackSnapshot>>.from(
          _projectionSubscriptions,
        );

    try {
      await Future.wait<void>(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    } finally {
      _subscriptions.clear();
      try {
        await _positionProjector.dispose();
      } finally {
        try {
          await _systemTimelineProjector.dispose();
        } finally {
          try {
            await Future.wait<void>(
              projectionSubscriptions.map(
                (subscription) => subscription.cancel(),
              ),
            );
          } finally {
            _projectionSubscriptions.clear();
            try {
              await _snapshotController.close();
            } finally {
              try {
                await _clock.dispose();
              } finally {
                await _engine.dispose();
              }
            }
          }
        }
      }
    }
  }

  Future<void> _commandNotReady(
    String command,
    CommandSource source, {
    bool notify = true,
  }) {
    if (notify) {
      _notifyCommandObserver(command, source);
    }
    return Future<void>.error(
      PlayerCommandFailure(
        code: 'commandUnavailable',
        message: 'Playback command is unavailable.',
        command: command,
      ),
    );
  }

  Future<void> _commandNoCurrentItem(
    String command,
    CommandSource source, {
    bool notify = true,
  }) {
    if (notify) {
      _notifyCommandObserver(command, source);
    }
    return Future<void>.error(
      PlayerCommandFailure(
        code: 'noCurrentItem',
        message: 'Playback command requires a current item.',
        command: command,
      ),
    );
  }

  Future<void> _commandSeekUnavailable(
    String command,
    CommandSource source, {
    bool notify = true,
  }) {
    if (notify) {
      _notifyCommandObserver(command, source);
    }
    return Future<void>.error(
      PlayerCommandFailure(
        code: 'seekUnavailableUnknownDuration',
        message: 'Seeking is unavailable without a known duration.',
        command: command,
      ),
    );
  }

  Future<void> _commandInvalidSpeed(
    String command,
    CommandSource source, {
    bool notify = true,
  }) {
    if (notify) {
      _notifyCommandObserver(command, source);
    }
    return Future<void>.error(
      const PlayerCommandFailure(
        code: 'invalidSpeed',
        message: 'Speed must be between 0.5 and 2.0.',
        command: 'setSpeed',
      ),
    );
  }

  void _notifyCommandObserver(String command, CommandSource source) {
    try {
      _commandObserver?.call(command, source);
    } catch (_) {
      // Observability must not change the command's typed failure contract.
    }
  }
}

final class _LoadFlight {
  _LoadFlight({this.generation});

  final LoadGeneration? generation;
  final Completer<void> _interruptCompleter = Completer<void>();
  bool wasInterrupted = false;

  Future<void> get interrupted => _interruptCompleter.future;

  void completeInterrupt() {
    wasInterrupted = true;
    if (!_interruptCompleter.isCompleted) {
      _interruptCompleter.complete();
    }
  }
}

final class _RestoreGraphContext {
  _RestoreGraphContext(this.sourceToken)
    : engineEvents = PendingLoadAccumulator();

  final PlaybackSourceToken sourceToken;
  final PendingLoadAccumulator engineEvents;
  final Completer<List<int>> _effectiveSequenceCompleter =
      Completer<List<int>>();
  List<int>? effectiveSequence;

  Future<List<int>> get effectiveSequenceFuture =>
      _effectiveSequenceCompleter.future;

  void recordEffectiveSequence(Iterable<int> sequence) {
    effectiveSequence = List<int>.unmodifiable(sequence);
    if (!_effectiveSequenceCompleter.isCompleted) {
      _effectiveSequenceCompleter.complete(effectiveSequence);
    }
  }
}

final class _RestoredGraph {
  const _RestoredGraph({
    required this.effectiveQueue,
    required this.effectiveSequence,
    required this.currentIndex,
  });

  final List<PlayerItem> effectiveQueue;
  final List<int> effectiveSequence;
  final int currentIndex;
}

final class _SeekConfirmation {
  const _SeekConfirmation({
    required this.sequence,
    required this.target,
    required this.sourceToken,
  });

  final int sequence;
  final Duration target;
  final PlaybackSourceToken sourceToken;
}

final class _PlayPauseIntent {
  _PlayPauseIntent({
    required this.desired,
    required this.sequence,
    required this.sourceToken,
  });

  final bool desired;
  final int sequence;
  final PlaybackSourceToken sourceToken;
  Future<void>? operation;
  bool dispatched = false;
}

final class _SpeedFlight {
  _SpeedFlight({
    required this.speed,
    required this.revision,
    required this.generation,
  });

  final double speed;
  final int revision;
  final LoadGeneration? generation;
  final Completer<void> _completer = Completer<void>();
  final Completer<void> confirmation = Completer<void>();

  bool dispatched = false;
  bool platformCompleted = false;
  bool confirmed = false;
  bool superseded = false;

  Future<void> get future => _completer.future;

  void completeSuccess() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}

final class _RepeatFlight {
  _RepeatFlight({
    required this.mode,
    required this.revision,
    required this.generation,
  });

  final PlayerRepeatMode mode;
  final int revision;
  final LoadGeneration? generation;
  final Completer<void> _completer = Completer<void>();
  final Completer<void> confirmation = Completer<void>();

  bool dispatched = false;
  bool platformCompleted = false;
  bool confirmed = false;
  bool superseded = false;

  Future<void> get future => _completer.future;

  void completeSuccess() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}

final class _ShuffleSequenceCandidate {
  _ShuffleSequenceCandidate({
    required Iterable<int> sequence,
    required this.revision,
    required this.generation,
    required this.eventEpoch,
  }) : sequence = List<int>.unmodifiable(sequence);

  final List<int> sequence;
  final int revision;
  final LoadGeneration? generation;
  final int eventEpoch;
}

final class _ShuffleFlight {
  _ShuffleFlight({
    required this.enabled,
    required this.revision,
    required this.generation,
    required this.anchorItem,
    required this.sequenceEpochAtDispatch,
  });

  final bool enabled;
  final int revision;
  final LoadGeneration? generation;
  final PlayerItem? anchorItem;
  final Completer<void> _completer = Completer<void>();
  final Completer<void> modeConfirmation = Completer<void>();
  final Completer<void> sequenceConfirmation = Completer<void>();
  int sequenceEpochAtDispatch;
  _ShuffleSequenceCandidate? sequenceCandidate;

  bool dispatched = false;
  bool platformCompleted = false;
  bool modeConfirmed = false;
  bool committed = false;
  bool superseded = false;

  Future<void> get future => _completer.future;

  void completeSuccess() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}
