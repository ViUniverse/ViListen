// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
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
  ]) : _clock = clock ?? PeriodicPlayerClock(),
       _commandObserver = commandObserver,
       _commandCoordinator =
           commandCoordinator ?? PlaybackCommandCoordinator() {
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
  ActivePlaybackContext? _active;
  PendingLoadContext? _pending;
  _LoadFlight? _activeLoad;
  _PlayPauseIntent? _playPauseIntent;
  int _nextSeekConfirmationSequence = 0;
  _SeekConfirmation? _pendingSeekConfirmation;
  int _nextPlayPauseSequence = 0;
  Future<void>? _disposeFuture;
  bool _disposed = false;

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
      ..add(_engine.speedStream.listen(_onSpeed))
      ..add(_engine.loopModeStream.listen(_onLoopMode))
      ..add(_engine.shuffleModeEnabledStream.listen(_onShuffleEnabled));
  }

  void _onPlayerState(just_audio.PlayerState state) {
    if (_routeToPending((events) => events.onPlayerState(state))) {
      return;
    }
    _reconcilePlayPauseConfirmation(state.playing);
    _reduceAndPublish(() => _snapshotReducer.onPlayerState(state));
  }

  void _onPosition(Duration position) {
    if (_routeToPending((events) => events.onPosition(position))) {
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
    if (_routeToPending(
      (events) => events.onBufferedPosition(bufferedPosition),
    )) {
      return;
    }
    _reduceAndPublish(
      () => _snapshotReducer.onBufferedPosition(bufferedPosition),
    );
  }

  void _onDuration(Duration? duration) {
    if (_routeToPending((events) => events.onDuration(duration))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onDuration(duration));
  }

  void _onCurrentIndex(int? currentIndex) {
    if (_routeToPending((events) => events.onCurrentIndex(currentIndex))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onCurrentIndex(currentIndex));
  }

  void _onSpeed(double speed) {
    if (_routeToPending((events) => events.onSpeed(speed))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onSpeed(speed));
  }

  void _onLoopMode(just_audio.LoopMode loopMode) {
    if (_routeToPending((events) => events.onLoopMode(loopMode))) {
      return;
    }
    _reduceAndPublish(() => _snapshotReducer.onLoopMode(loopMode));
  }

  void _onShuffleEnabled(bool enabled) {
    if (_routeToPending((events) => events.onShuffleEnabled(enabled))) {
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
    _playPauseIntent = null;
    _pendingSeekConfirmation = null;

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

      // Keep the active tuple outward during replacement. For an initial load
      // the reducer's canonical tuple is already empty. Pending projections
      // stay internal until a later load-commit task confirms this generation.
      _reduceAndPublish(_snapshotReducer.onLoadStarted);

      final flight = _LoadFlight();
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
          Error.throwWithStackTrace(error, stackTrace);
        }
      } finally {
        if (identical(_activeLoad, flight)) {
          _activeLoad = null;
        }
      }

      // PLR-063 will commit only this still-current context. Keep the check at
      // the load boundary so a stale completion cannot accidentally become a
      // publication when that commit path is added.
      if (_disposed ||
          !identical(_pending, pending) ||
          !_commandCoordinator.isCurrent(generation)) {
        return;
      }

      _commitPendingLoad(pending);

      if (pending.desiredPlaying && _commandCoordinator.isCurrent(generation)) {
        _startAutoplay(generation);
      }
    }, interrupt: _interruptCurrentLoad);
  }

  void _commitPendingLoad(PendingLoadContext pending) {
    final events = pending.engineEvents;
    final eventIndex = events.currentIndex;
    final currentIndex =
        events.hasCurrentIndex &&
            eventIndex != null &&
            eventIndex >= 0 &&
            eventIndex < pending.targetQueue.length
        ? eventIndex
        : pending.targetIndex;

    _snapshotReducer.commitQueue(
      pending.targetQueue,
      currentIndex: currentIndex,
    );
    if (events.hasPosition) {
      _snapshotReducer.onPosition(events.position!);
    }
    if (events.hasBufferedPosition) {
      _snapshotReducer.onBufferedPosition(events.bufferedPosition!);
    }
    if (events.hasDuration) {
      _snapshotReducer.onDuration(events.duration);
    }
    if (events.hasSpeed) {
      _snapshotReducer.onSpeed(events.speed!);
    }
    if (events.hasLoopMode) {
      _snapshotReducer.onLoopMode(events.loopMode!);
    }
    if (events.hasShuffleEnabled) {
      _snapshotReducer.onShuffleEnabled(events.shuffleEnabled!);
    }

    // Load is prepare-only. A pending player-state event cannot confirm
    // autoplay, so every successful load is committed as ready and paused.
    final committed = _snapshotReducer.onPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    _pending = null;
    _active = ActivePlaybackContext(
      logicalQueue: pending.targetQueue,
      effectiveQueue: pending.targetQueue,
      currentIndex: committed.currentIndex,
      position: committed.position,
      desiredPlaying: pending.desiredPlaying,
    );

    _routeImmediate(committed);
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
        platformCall: (intent) =>
            _runReplay(intent, item: currentItem, index: currentIndex),
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
  }) async {
    await _engine.seek(Duration.zero, index: index);
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
      _commandNotReady('next', source);

  @override
  Future<void> handlePrevious(CommandSource source) =>
      _commandNotReady('previous', source);

  @override
  Future<void> handleSetSpeed(double speed, CommandSource source) =>
      _commandNotReady('setSpeed', source);

  @override
  Future<void> handleSetRepeatMode(
    PlayerRepeatMode mode,
    CommandSource source,
  ) => _commandNotReady('setRepeatMode', source);

  @override
  Future<void> handleSetShuffleEnabled(bool enabled, CommandSource source) =>
      _commandNotReady('setShuffleEnabled', source);

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

  void _notifyCommandObserver(String command, CommandSource source) {
    try {
      _commandObserver?.call(command, source);
    } catch (_) {
      // Observability must not change the command's typed failure contract.
    }
  }
}

final class _LoadFlight {
  final Completer<void> _interruptCompleter = Completer<void>();

  Future<void> get interrupted => _interruptCompleter.future;

  void completeInterrupt() {
    if (!_interruptCompleter.isCompleted) {
      _interruptCompleter.complete();
    }
  }
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
