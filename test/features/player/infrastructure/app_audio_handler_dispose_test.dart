// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import 'package:vi_listen/features/player/infrastructure/player_clock.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';

void main() {
  late _TrackingPlaybackEngine engine;
  late _TrackingPlayerClock clock;
  late AppAudioHandler handler;

  setUp(() {
    engine = _TrackingPlaybackEngine();
    clock = _TrackingPlayerClock();
    handler = AppAudioHandler(engine, clock);
  });

  tearDown(() async {
    engine.releaseDispose();
    await handler.dispose();
  });

  test('dispose cancels all owned subscriptions exactly once', () async {
    final snapshots = <PlaybackSnapshot>[];
    var snapshotDoneCount = 0;
    final snapshotSubscription = handler.snapshots.listen(
      snapshots.add,
      onDone: () => snapshotDoneCount += 1,
    );

    await pumpEventQueue();
    expect(snapshots, [PlaybackSnapshot.idle]);
    expect(engine.sourceEventsTracker.listenCount, 1);
    expect(clock.ticksTracker.listenCount, 2);

    await handler.dispose();

    expect(engine.sourceEventsTracker.cancelCount, 1);
    expect(clock.ticksTracker.cancelCount, 2);
    expect(clock.disposeCount, 1);
    expect(engine.disposeCount, 1);
    expect(snapshotDoneCount, 1);

    await snapshotSubscription.cancel();
  });

  test('events after dispose begins are ignored safely', () async {
    final snapshots = <PlaybackSnapshot>[];
    final mediaItems = <audio_service.MediaItem?>[];
    final queues = <List<audio_service.MediaItem>>[];
    final playbackStates = <audio_service.PlaybackState>[];

    final snapshotSubscription = handler.snapshots.listen(snapshots.add);
    final mediaItemSubscription = handler.mediaItem.listen(mediaItems.add);
    final queueSubscription = handler.queue.listen(queues.add);
    final playbackStateSubscription = handler.playbackState.listen(
      playbackStates.add,
    );

    await pumpEventQueue();
    final snapshotCount = snapshots.length;
    final mediaItemCount = mediaItems.length;
    final queueCount = queues.length;
    final playbackStateCount = playbackStates.length;

    engine.delayDispose = true;
    final disposeFuture = handler.dispose();
    await engine.disposeStarted.future;

    engine.emit((
      sourceGeneration: 0,
      type: PlaybackEngineEventType.playerState,
      value: PlayerState(false, ProcessingState.ready),
    ));
    await pumpEventQueue();

    expect(snapshots, hasLength(snapshotCount));
    expect(mediaItems, hasLength(mediaItemCount));
    expect(queues, hasLength(queueCount));
    expect(playbackStates, hasLength(playbackStateCount));

    engine.releaseDispose();
    await disposeFuture;

    final postDisposeSnapshots = <PlaybackSnapshot>[];
    var postDisposeDoneCount = 0;
    final postDisposeSubscription = handler.snapshots.listen(
      postDisposeSnapshots.add,
      onDone: () => postDisposeDoneCount += 1,
    );
    await pumpEventQueue();

    expect(postDisposeSnapshots, isEmpty);
    expect(postDisposeDoneCount, 1);

    await postDisposeSubscription.cancel();
    await snapshotSubscription.cancel();
    await mediaItemSubscription.cancel();
    await queueSubscription.cancel();
    await playbackStateSubscription.cancel();
  });

  test('double dispose is idempotent and does not crash', () async {
    final firstDispose = handler.dispose();
    final secondDispose = handler.dispose();

    await Future.wait<void>([firstDispose, secondDispose]);

    expect(engine.sourceEventsTracker.cancelCount, 1);
    expect(clock.ticksTracker.cancelCount, 2);
    expect(clock.disposeCount, 1);
    expect(engine.disposeCount, 1);
  });

  test('reentrant dispose joins the cleanup already in progress', () async {
    Future<void>? reentrantDispose;
    engine.sourceEventsTracker.onCancel = () {
      reentrantDispose = handler.dispose();
    };

    await handler.dispose();
    await reentrantDispose;

    expect(engine.sourceEventsTracker.cancelCount, 1);
    expect(clock.ticksTracker.cancelCount, 2);
    expect(clock.disposeCount, 1);
    expect(engine.disposeCount, 1);
  });

  test('Cubit close does not dispose the handler', () async {
    final cubit = PlayerCubit(UiPlaybackGatewayAdapter(handler));

    await cubit.close();

    expect(engine.disposeCount, 0);
    expect(clock.disposeCount, 0);

    await handler.dispose();

    expect(engine.disposeCount, 1);
    expect(clock.disposeCount, 1);
  });
}

final class _TrackingStream<T> {
  _TrackingStream() : _controller = StreamController<T>.broadcast(sync: true);

  final StreamController<T> _controller;
  int listenCount = 0;
  int cancelCount = 0;
  void Function()? onCancel;

  Stream<T> get stream => Stream<T>.multi((multi) {
    listenCount += 1;
    late final StreamSubscription<T> subscription;
    subscription = _controller.stream.listen(
      multi.add,
      onError: (Object error, StackTrace stackTrace) {
        multi.addError(error, stackTrace);
      },
      onDone: multi.close,
    );
    multi.onCancel = () {
      cancelCount += 1;
      onCancel?.call();
      return subscription.cancel();
    };
  }, isBroadcast: true);

  void add(T value) => _controller.add(value);

  Future<void> close() => _controller.close();
}

final class _TrackingPlayerClock implements PlayerClock {
  final _TrackingStream<Duration> _ticks = _TrackingStream<Duration>();
  int disposeCount = 0;
  final Duration _elapsed = Duration.zero;
  Future<void>? _disposeFuture;

  _TrackingStream<Duration> get ticksTracker => _ticks;

  @override
  Stream<Duration> get ticks => _ticks.stream;

  @override
  Duration get elapsed => _elapsed;

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }

    disposeCount += 1;
    return _disposeFuture = _ticks.close();
  }
}

final class _TrackingPlaybackEngine implements PlaybackEngine {
  final _sourceEvents = _TrackingStream<PlaybackEngineEvent>();
  final Completer<void> disposeStarted = Completer<void>();
  final Completer<void> _disposeGate = Completer<void>();

  bool delayDispose = false;
  int disposeCount = 0;
  Future<void>? _disposeFuture;

  _TrackingStream<PlaybackEngineEvent> get sourceEventsTracker => _sourceEvents;

  @override
  Stream<PlaybackEngineEvent> get sourceEvents => _sourceEvents.stream;

  @override
  Stream<PlayerState> get playerStateStream => Stream<PlayerState>.empty();

  @override
  Stream<Duration> get positionStream => Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferedPositionStream => Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => Stream<Duration?>.empty();

  @override
  Stream<int?> get currentIndexStream => Stream<int?>.empty();

  @override
  Stream<List<int>> get effectiveSequenceStream => Stream<List<int>>.empty();

  @override
  Stream<double> get speedStream => Stream<double>.empty();

  @override
  Stream<LoopMode> get loopModeStream => Stream<LoopMode>.empty();

  @override
  Stream<bool> get shuffleModeEnabledStream => Stream<bool>.empty();

  @override
  Stream<PlayerException> get errorStream => Stream<PlayerException>.empty();

  @override
  Future<void> load(
    List<AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  }) async {}

  @override
  Future<void> interruptLoad() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }

    disposeCount += 1;
    disposeStarted.complete();
    return _disposeFuture = _disposeResources();
  }

  Future<void> _disposeResources() async {
    if (delayDispose) {
      await _disposeGate.future;
    }
    await _sourceEvents.close();
  }

  void emit(PlaybackEngineEvent event) => _sourceEvents.add(event);

  void releaseDispose() {
    if (!_disposeGate.isCompleted) {
      _disposeGate.complete();
    }
  }
}
