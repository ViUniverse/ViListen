// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/just_audio_playback_engine.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import 'package:vi_listen/features/player/infrastructure/playback_mappers.dart';
import 'package:vi_listen/features/player/infrastructure/playback_publication_diff.dart';
import 'package:vi_listen/features/player/infrastructure/playback_snapshot_reducer.dart';
import 'package:vi_listen/features/player/infrastructure/periodic_player_clock.dart';
import 'package:vi_listen/features/player/infrastructure/player_clock.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_command_target.dart';

/// Observes command ingress without coupling the handler to a logging or
/// analytics implementation.
typedef PlaybackCommandObserver =
    void Function(String command, CommandSource source);

/// Audio service owner and internal playback command target.
///
/// PLR-060 establishes ownership and lifecycle seams. Engine stream events are
/// reduced into domain snapshots here; commands and platform publications are
/// layered on by the subsequent handler tasks.
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
  ]) : _clock = clock ?? PeriodicPlayerClock(),
       _commandObserver = commandObserver {
    _bindEngineStreams();
  }

  final PlaybackEngine _engine;
  final PlayerClock _clock;
  final PlaybackCommandObserver? _commandObserver;
  final StreamController<PlaybackSnapshot> _snapshotController =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final PlaybackSnapshotReducer _snapshotReducer = PlaybackSnapshotReducer();

  PlaybackSnapshot _latestSnapshot = PlaybackSnapshot.idle;
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
    _reduceAndPublish(() => _snapshotReducer.onPlayerState(state));
  }

  void _onPosition(Duration position) {
    if (_disposed) {
      return;
    }

    // Position is retained as the reducer's raw candidate. PLR-065/068 own
    // cadence and will publish it through their respective projectors.
    _snapshotReducer.onPosition(position);
  }

  void _onBufferedPosition(Duration bufferedPosition) {
    _reduceAndPublish(
      () => _snapshotReducer.onBufferedPosition(bufferedPosition),
    );
  }

  void _onDuration(Duration? duration) {
    _reduceAndPublish(() => _snapshotReducer.onDuration(duration));
  }

  void _onCurrentIndex(int? currentIndex) {
    _reduceAndPublish(() => _snapshotReducer.onCurrentIndex(currentIndex));
  }

  void _onSpeed(double speed) {
    _reduceAndPublish(() => _snapshotReducer.onSpeed(speed));
  }

  void _onLoopMode(just_audio.LoopMode loopMode) {
    _reduceAndPublish(() => _snapshotReducer.onLoopMode(loopMode));
  }

  void _onShuffleEnabled(bool enabled) {
    _reduceAndPublish(() => _snapshotReducer.onShuffleEnabled(enabled));
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

    // Keep replay state in sync before handing the value to any subscriber.
    _latestSnapshot = reduced;
    if (!diff.snapshotChanged) {
      return;
    }

    _snapshotController.add(reduced);
  }

  @override
  Future<void> handleLoadQueue(
    List<PlayerItem> items,
    int initialIndex,
    bool autoplay,
    CommandSource source,
  ) => _commandNotReady('loadQueue', source);

  @override
  Future<void> handlePlay(CommandSource source) =>
      _commandNotReady('play', source);

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

    try {
      await Future.wait<void>(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    } finally {
      _subscriptions.clear();
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
