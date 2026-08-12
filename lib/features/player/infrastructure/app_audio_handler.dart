// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
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

      if (pending.autoplay && _commandCoordinator.isCurrent(generation)) {
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
      desiredPlaying: pending.autoplay,
    );

    _routeImmediate(committed);
  }

  void _startAutoplay(LoadGeneration generation) {
    if (_disposed || !_commandCoordinator.isCurrent(generation)) {
      return;
    }

    Future<void> playFuture;
    try {
      playFuture = _engine.play();
    } catch (_) {
      _publishPausedAfterAutoplayFailure(generation);
      return;
    }

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
    final snapshot = _latestSnapshot;
    final currentItem = snapshot.currentItem;
    final currentIndex = snapshot.currentIndex;
    if (!_canReplay(snapshot, currentItem, currentIndex)) {
      return _commandNotReady('play', source);
    }

    final replay = _ReplayContext(
      sourceToken: _commandCoordinator.captureSourceToken(),
      item: currentItem!,
      index: currentIndex!,
    );
    _notifyCommandObserver('play', source);
    return _commandCoordinator.setDesiredPlaying(
      true,
      () => _runReplay(replay),
    );
  }

  bool _canReplay(
    PlaybackSnapshot snapshot,
    PlayerItem? currentItem,
    int? currentIndex,
  ) {
    if (!snapshot.isCompleted || snapshot.playing) {
      return false;
    }

    if (currentItem == null || currentIndex == null) {
      return false;
    }

    return currentIndex >= 0 &&
        currentIndex < snapshot.queue.length &&
        snapshot.queue[currentIndex] == currentItem;
  }

  Future<void> _runReplay(_ReplayContext replay) async {
    await _engine.seek(Duration.zero, index: replay.index);
    if (!_isReplayCurrent(replay)) {
      return;
    }

    await _engine.play();
  }

  bool _isReplayCurrent(_ReplayContext replay) =>
      !_disposed &&
      _commandCoordinator.isSourceTokenCurrent(replay.sourceToken) &&
      _latestSnapshot.currentIndex == replay.index &&
      _latestSnapshot.currentItem == replay.item;

  @override
  Future<void> handlePause(CommandSource source) =>
      _commandNotReady('pause', source);

  @override
  Future<void> handleStop(CommandSource source) =>
      _commandNotReady('stop', source);

  @override
  Future<void> handleSeek(Duration position, CommandSource source) =>
      _commandNotReady('seek', source);

  @override
  Future<void> handleSkipBy(Duration offset, CommandSource source) =>
      _commandNotReady('skipBy', source);

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

  Future<void> _commandNotReady(String command, CommandSource source) {
    _notifyCommandObserver(command, source);
    return Future<void>.error(
      PlayerCommandFailure(
        code: 'commandUnavailable',
        message: 'Playback command is unavailable.',
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

final class _ReplayContext {
  const _ReplayContext({
    required this.sourceToken,
    required this.item,
    required this.index,
  });

  final PlaybackSourceToken sourceToken;
  final PlayerItem item;
  final int index;
}
