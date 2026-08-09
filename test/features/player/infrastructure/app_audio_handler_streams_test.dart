// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';

void main() {
  late FakePlaybackEngine engine;
  late AppAudioHandler handler;

  setUp(() {
    engine = FakePlaybackEngine();
    handler = AppAudioHandler(engine, FakePlayerClock());
  });

  tearDown(() async {
    await handler.dispose();
  });

  Future<List<PlaybackSnapshot>> listenWithInitialSnapshot() async {
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(snapshots, [PlaybackSnapshot.idle]);
    return snapshots;
  }

  test('reduces each bound stream into its related snapshot field', () async {
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    engine.emitPlayerState(PlayerState(false, ProcessingState.ready));
    await pumpEventQueue();
    var previous = snapshots.last;
    expect(previous.processingState.name, 'ready');
    expect(previous.playing, isFalse);

    engine.emitBufferedPosition(const Duration(seconds: 12));
    await pumpEventQueue();
    var current = snapshots.last;
    expect(current.bufferedPosition, const Duration(seconds: 12));
    _expectUnchangedExcept(previous, current, _SnapshotField.bufferedPosition);
    previous = current;

    engine.emitDuration(const Duration(seconds: 30));
    await pumpEventQueue();
    current = snapshots.last;
    expect(current.duration, const Duration(seconds: 30));
    _expectUnchangedExcept(previous, current, _SnapshotField.duration);
    previous = current;

    engine.emitSpeed(1.5);
    await pumpEventQueue();
    current = snapshots.last;
    expect(current.speed, 1.5);
    _expectUnchangedExcept(previous, current, _SnapshotField.speed);
    previous = current;

    engine.emitLoopMode(LoopMode.one);
    await pumpEventQueue();
    current = snapshots.last;
    expect(current.repeatMode, PlayerRepeatMode.one);
    _expectUnchangedExcept(previous, current, _SnapshotField.repeatMode);
    previous = current;

    engine.emitShuffleModeEnabled(true);
    await pumpEventQueue();
    current = snapshots.last;
    expect(current.shuffleEnabled, isTrue);
    _expectUnchangedExcept(previous, current, _SnapshotField.shuffleEnabled);

    // The handler has no committed queue in PLR-061, so every index is
    // normalized to the same null item/index tuple.
    engine.emitCurrentIndex(0);
    engine.emitCurrentIndex(-1);
    engine.emitCurrentIndex(null);
    await pumpEventQueue();
    expect(snapshots.last.currentIndex, isNull);
    expect(snapshots.last.currentItem, isNull);
  });

  test('does not emit identical engine events', () async {
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    engine.emitPlayerState(PlayerState(false, ProcessingState.idle));
    engine.emitPosition(Duration.zero);
    engine.emitBufferedPosition(Duration.zero);
    engine.emitDuration(null);
    engine.emitCurrentIndex(null);
    engine.emitSpeed(1.0);
    engine.emitLoopMode(LoopMode.off);
    engine.emitShuffleModeEnabled(false);
    await pumpEventQueue();

    expect(snapshots, [PlaybackSnapshot.idle]);
  });

  test('replays the latest reduced snapshot asynchronously', () async {
    final initialSubscription = handler.snapshots.listen((_) {});
    addTearDown(initialSubscription.cancel);
    await pumpEventQueue();

    engine.emitSpeed(1.25);
    await pumpEventQueue();

    final replayed = <PlaybackSnapshot>[];
    final lateSubscription = handler.snapshots.listen(replayed.add);
    addTearDown(lateSubscription.cancel);

    expect(replayed, isEmpty);
    await pumpEventQueue();
    expect(replayed, [PlaybackSnapshot.idle.copyWith(speed: 1.25)]);
  });

  test('pause at ready keeps processing ready', () async {
    final snapshots = await listenWithInitialSnapshot();

    engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
    engine.emitPlayerState(PlayerState(false, ProcessingState.ready));
    await pumpEventQueue();

    expect(snapshots.last.processingState, PlaybackProcessingState.ready);
    expect(snapshots.last.playing, isFalse);
  });

  test('playing at buffering keeps playing true and buffering state', () async {
    final snapshots = await listenWithInitialSnapshot();

    engine.emitPlayerState(PlayerState(true, ProcessingState.buffering));
    await pumpEventQueue();

    expect(snapshots.last.processingState.name, 'buffering');
    expect(snapshots.last.playing, isTrue);
  });

  test('a paused position candidate keeps playing false', () async {
    final snapshots = await listenWithInitialSnapshot();

    engine.emitPlayerState(PlayerState(false, ProcessingState.ready));
    await pumpEventQueue();
    engine.emitPosition(const Duration(seconds: 7));
    await pumpEventQueue();

    // Position is a candidate only until an immediate lifecycle event arrives.
    expect(snapshots.last.position, Duration.zero);

    engine.emitPlayerState(PlayerState(false, ProcessingState.ready));
    await pumpEventQueue();

    expect(snapshots.last.position, const Duration(seconds: 7));
    expect(snapshots.last.processingState, PlaybackProcessingState.ready);
    expect(snapshots.last.playing, isFalse);
  });

  test('coalesces position candidate into the next lifecycle event', () async {
    final snapshots = await listenWithInitialSnapshot();

    engine.emitPlayerState(PlayerState(false, ProcessingState.ready));
    await pumpEventQueue();
    final countBeforePosition = snapshots.length;

    engine.emitPosition(const Duration(seconds: 11));
    await pumpEventQueue();
    expect(snapshots, hasLength(countBeforePosition));

    engine.emitPlayerState(PlayerState(false, ProcessingState.ready));
    await pumpEventQueue();
    expect(snapshots, hasLength(countBeforePosition + 1));
    expect(snapshots.last.position, const Duration(seconds: 11));
  });

  test('normalizes null duration to zero', () async {
    final snapshots = await listenWithInitialSnapshot();

    engine.emitDuration(const Duration(seconds: 20));
    await pumpEventQueue();
    engine.emitDuration(null);
    await pumpEventQueue();

    expect(snapshots.last.duration, Duration.zero);
  });

  test('keeps null and out-of-range index/item tuple consistent', () async {
    final snapshots = await listenWithInitialSnapshot();

    for (final index in <int?>[null, 0, -1, 1]) {
      engine.emitCurrentIndex(index);
      await pumpEventQueue();

      expect(snapshots.last.currentIndex, isNull);
      expect(snapshots.last.currentItem, isNull);
    }
  });

  test(
    'dispose cancels stream handling and makes in-flight events inert',
    () async {
      final snapshots = await listenWithInitialSnapshot();
      final disposeFuture = handler.dispose();

      // AppAudioHandler marks itself disposed before awaiting cancellation.
      engine.emitPlayerState(PlayerState(true, ProcessingState.ready));
      engine.emitPosition(const Duration(seconds: 5));
      await disposeFuture;

      expect(snapshots, [PlaybackSnapshot.idle]);
      expect(engine.disposeCount, 1);
    },
  );

  test('engine stream binding does not issue commands', () async {
    final snapshots = await listenWithInitialSnapshot();

    engine.emitPlayerState(PlayerState(true, ProcessingState.buffering));
    engine.emitPosition(const Duration(seconds: 4));
    engine.emitBufferedPosition(const Duration(seconds: 6));
    engine.emitDuration(const Duration(seconds: 40));
    engine.emitCurrentIndex(null);
    engine.emitSpeed(1.25);
    engine.emitLoopMode(LoopMode.all);
    engine.emitShuffleModeEnabled(true);
    await pumpEventQueue();

    expect(snapshots, isNotEmpty);
    expect(engine.calls, isEmpty);
  });
}

enum _SnapshotField {
  bufferedPosition,
  duration,
  speed,
  repeatMode,
  shuffleEnabled,
}

void _expectUnchangedExcept(
  PlaybackSnapshot previous,
  PlaybackSnapshot current,
  _SnapshotField field,
) {
  if (field != _SnapshotField.bufferedPosition) {
    expect(current.bufferedPosition, previous.bufferedPosition);
  }
  if (field != _SnapshotField.duration) {
    expect(current.duration, previous.duration);
  }
  if (field != _SnapshotField.speed) {
    expect(current.speed, previous.speed);
  }
  if (field != _SnapshotField.repeatMode) {
    expect(current.repeatMode, previous.repeatMode);
  }
  if (field != _SnapshotField.shuffleEnabled) {
    expect(current.shuffleEnabled, previous.shuffleEnabled);
  }
  expect(current.position, previous.position);
  expect(current.currentItem, previous.currentItem);
  expect(current.currentIndex, previous.currentIndex);
  expect(current.processingState, previous.processingState);
  expect(current.playing, previous.playing);
  expect(current.queue, previous.queue);
  expect(current.failure, previous.failure);
}
