// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/playback_snapshot_reducer.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';

void main() {
  late final itemA = testPlayerItem(id: 'track-a');
  late final itemB = testPlayerItem(id: 'track-b');

  test('merges player state without changing unrelated fields', () {
    final initial = _activeSnapshot(
      queue: [itemA, itemB],
      currentItem: itemA,
      currentIndex: 0,
    );
    final reducer = PlaybackSnapshotReducer(initial: initial);

    final result = reducer.onPlayerState(
      PlayerState(true, ProcessingState.buffering),
    );

    expect(result.processingState, PlaybackProcessingState.buffering);
    expect(result.playing, isTrue);
    _expectTimelineAndMetadataUnchanged(result, initial);
  });

  test('each timeline and option event changes only its related field', () {
    final initial = _activeSnapshot(
      queue: [itemA, itemB],
      currentItem: itemA,
      currentIndex: 0,
    );
    final reducer = PlaybackSnapshotReducer(initial: initial);

    final positionResult = reducer.onPosition(const Duration(seconds: 9));
    expect(positionResult.position, const Duration(seconds: 9));
    expect(positionResult.bufferedPosition, initial.bufferedPosition);
    expect(positionResult.duration, initial.duration);

    final bufferResult = reducer.onBufferedPosition(
      const Duration(seconds: 15),
    );
    expect(bufferResult.bufferedPosition, const Duration(seconds: 15));
    expect(bufferResult.position, positionResult.position);
    expect(bufferResult.duration, initial.duration);

    final speedResult = reducer.onSpeed(1.75);
    expect(speedResult.speed, 1.75);
    expect(speedResult.position, bufferResult.position);
    expect(speedResult.bufferedPosition, bufferResult.bufferedPosition);

    final repeatResult = reducer.onLoopMode(LoopMode.all);
    expect(repeatResult.repeatMode, PlayerRepeatMode.all);
    expect(repeatResult.speed, speedResult.speed);

    final shuffleResult = reducer.onShuffleEnabled(false);
    expect(shuffleResult.shuffleEnabled, isFalse);
    expect(shuffleResult.repeatMode, repeatResult.repeatMode);
  });

  test('duration arriving after ready changes only duration', () {
    final initial = _activeSnapshot(
      queue: [itemA],
      currentItem: itemA,
      currentIndex: 0,
      duration: Duration.zero,
      position: const Duration(seconds: 4),
      bufferedPosition: const Duration(seconds: 5),
    );
    final reducer = PlaybackSnapshotReducer(initial: initial);

    final result = reducer.onDuration(const Duration(seconds: 20));

    expect(result.processingState, PlaybackProcessingState.ready);
    expect(result.playing, isTrue);
    expect(result.position, initial.position);
    expect(result.bufferedPosition, initial.bufferedPosition);
    expect(result.duration, const Duration(seconds: 20));
    expect(result.failure, isNull);
  });

  test('normalizes unknown duration to zero', () {
    final reducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA],
        currentItem: itemA,
        currentIndex: 0,
        duration: const Duration(seconds: 20),
      ),
    );

    expect(reducer.onDuration(null).duration, Duration.zero);
    expect(
      reducer.onDuration(const Duration(seconds: -1)).duration,
      Duration.zero,
    );
  });

  test('keeps raw position when duration becomes smaller than position', () {
    final initial = _activeSnapshot(
      queue: [itemA],
      currentItem: itemA,
      currentIndex: 0,
      position: const Duration(seconds: 20),
      duration: const Duration(seconds: 30),
    );
    final reducer = PlaybackSnapshotReducer(initial: initial);

    final result = reducer.onDuration(const Duration(seconds: 10));

    expect(result.position, const Duration(seconds: 20));
    expect(result.duration, const Duration(seconds: 10));
    expect(result.progress, 1.0);
    expect(result.remaining, Duration.zero);
  });

  test('selects the current item and index together', () {
    final reducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA, itemB],
        currentItem: itemA,
        currentIndex: 0,
      ),
    );

    final result = reducer.onCurrentIndex(1);

    expect(result.currentIndex, 1);
    expect(result.currentItem, itemB);
    expect(result.queue, [itemA, itemB]);
  });

  test('normalizes null and invalid indexes to a null item/index pair', () {
    final reducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA, itemB],
        currentItem: itemA,
        currentIndex: 0,
      ),
    );

    for (final index in <int?>[null, -1, 2]) {
      final result = reducer.onCurrentIndex(index);

      expect(result.currentIndex, isNull);
      expect(result.currentItem, isNull);
      expect(result.queue, [itemA, itemB]);
    }
  });

  test('keeps failure when a late player state arrives', () {
    const failure = PlayerFailure(
      code: 'network',
      message: 'Network unavailable.',
      isRecoverable: true,
      itemId: 'track-a',
    );
    for (final processingState in [
      ProcessingState.ready,
      ProcessingState.buffering,
    ]) {
      final reducer = PlaybackSnapshotReducer(
        initial: _activeSnapshot(
          queue: [itemA],
          currentItem: itemA,
          currentIndex: 0,
        ),
      );

      reducer.onFailure(failure, preserveConfirmedPlaying: false);
      final result = reducer.onPlayerState(PlayerState(true, processingState));

      expect(result.failure, failure);
      expect(result.processingState, PlaybackProcessingState.error);
      expect(result.playing, isFalse);
    }
  });

  test('stopFailed follows the latest engine-confirmed playing value', () {
    const failure = PlayerFailure(
      code: 'stopFailed',
      message: 'Playback could not be stopped.',
      isRecoverable: false,
    );
    final reducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA],
        currentItem: itemA,
        currentIndex: 0,
        playing: false,
      ),
    );

    reducer.onFailure(failure, preserveConfirmedPlaying: true);
    final playing = reducer.onPlayerState(
      PlayerState(true, ProcessingState.ready),
    );
    final paused = reducer.onPlayerState(
      PlayerState(false, ProcessingState.buffering),
    );

    expect(playing.failure, failure);
    expect(playing.playing, isTrue);
    expect(paused.failure, failure);
    expect(paused.playing, isFalse);
  });

  test('load start is the explicit failure recovery transition', () {
    const failure = PlayerFailure(
      code: 'network',
      message: 'Network unavailable.',
      isRecoverable: true,
      itemId: 'track-a',
    );
    final initial = _activeSnapshot(
      queue: [itemA],
      currentItem: itemA,
      currentIndex: 0,
    );
    final reducer = PlaybackSnapshotReducer(initial: initial);
    reducer.onFailure(failure, preserveConfirmedPlaying: false);

    final result = reducer.onLoadStarted();

    expect(result.processingState, PlaybackProcessingState.loading);
    expect(result.failure, isNull);
    expect(result.currentItem, initial.currentItem);
    expect(result.queue, initial.queue);
    expect(result.position, initial.position);
  });

  test('initial load start keeps the canonical empty metadata', () {
    final result = PlaybackSnapshotReducer().onLoadStarted();

    expect(result.processingState, PlaybackProcessingState.loading);
    expect(result.currentItem, isNull);
    expect(result.currentIndex, isNull);
    expect(result.queue, isEmpty);
  });

  test('failure policy preserves confirmed playing only when requested', () {
    const failure = PlayerFailure(
      code: 'stopFailed',
      message: 'Playback could not be stopped.',
      isRecoverable: false,
    );
    final playingReducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA],
        currentItem: itemA,
        currentIndex: 0,
        playing: true,
      ),
    );
    final pausedReducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA],
        currentItem: itemA,
        currentIndex: 0,
        playing: false,
      ),
    );

    expect(
      playingReducer.onFailure(failure, preserveConfirmedPlaying: true).playing,
      isTrue,
    );
    expect(
      pausedReducer.onFailure(failure, preserveConfirmedPlaying: true).playing,
      isFalse,
    );
    expect(
      playingReducer
          .onFailure(failure, preserveConfirmedPlaying: false)
          .playing,
      isFalse,
    );
  });

  test('commitSnapshot replaces queue and timeline as one complete state', () {
    final active = _activeSnapshot(
      queue: [itemA],
      currentItem: itemA,
      currentIndex: 0,
      position: const Duration(seconds: 18),
      bufferedPosition: const Duration(seconds: 19),
      duration: const Duration(seconds: 30),
    );
    final reducer = PlaybackSnapshotReducer(initial: active);
    final pending = buildPlaybackSnapshot(
      currentItem: itemA,
      queue: [itemA, itemB],
      currentIndex: 1,
      processingState: PlaybackProcessingState.ready,
      playing: false,
      position: const Duration(seconds: 2),
      bufferedPosition: const Duration(seconds: 4),
      duration: const Duration(seconds: 60),
      speed: 1.25,
      repeatMode: PlayerRepeatMode.all,
      shuffleEnabled: true,
    );

    final result = reducer.commitSnapshot(pending);

    expect(result.queue, [itemA, itemB]);
    expect(result.currentIndex, 1);
    expect(result.currentItem, itemB);
    expect(result.position, const Duration(seconds: 2));
    expect(result.bufferedPosition, const Duration(seconds: 4));
    expect(result.duration, const Duration(seconds: 60));
    expect(result.speed, 1.25);
    expect(result.repeatMode, PlayerRepeatMode.all);
    expect(result.shuffleEnabled, isTrue);
  });

  test('commitQueue keeps effective queue and selected tuple consistent', () {
    final reducer = PlaybackSnapshotReducer(
      initial: _activeSnapshot(
        queue: [itemA],
        currentItem: itemA,
        currentIndex: 0,
      ),
    );

    final valid = reducer.commitQueue([itemB, itemA], currentIndex: 1);
    expect(valid.queue, [itemB, itemA]);
    expect(valid.currentIndex, 1);
    expect(valid.currentItem, itemA);

    final nullIndex = reducer.commitQueue([itemB, itemA], currentIndex: null);
    expect(nullIndex.queue, [itemB, itemA]);
    expect(nullIndex.currentIndex, isNull);
    expect(nullIndex.currentItem, isNull);

    final outOfRange = reducer.commitQueue([itemB, itemA], currentIndex: 2);
    expect(outOfRange.queue, [itemB, itemA]);
    expect(outOfRange.currentIndex, isNull);
    expect(outOfRange.currentItem, isNull);
  });
}

PlaybackSnapshot _activeSnapshot({
  required List<PlayerItem> queue,
  required PlayerItem? currentItem,
  required int? currentIndex,
  PlaybackProcessingState processingState = PlaybackProcessingState.ready,
  bool playing = true,
  Duration position = const Duration(seconds: 8),
  Duration bufferedPosition = const Duration(seconds: 12),
  Duration duration = const Duration(seconds: 20),
  double speed = 1.5,
  PlayerRepeatMode repeatMode = PlayerRepeatMode.one,
  bool shuffleEnabled = true,
}) => buildPlaybackSnapshot(
  currentItem: currentItem,
  queue: queue,
  currentIndex: currentIndex,
  processingState: processingState,
  playing: playing,
  position: position,
  bufferedPosition: bufferedPosition,
  duration: duration,
  speed: speed,
  repeatMode: repeatMode,
  shuffleEnabled: shuffleEnabled,
);

void _expectTimelineAndMetadataUnchanged(
  PlaybackSnapshot actual,
  PlaybackSnapshot expected,
) {
  expect(actual.currentItem, expected.currentItem);
  expect(actual.queue, expected.queue);
  expect(actual.currentIndex, expected.currentIndex);
  expect(actual.position, expected.position);
  expect(actual.bufferedPosition, expected.bufferedPosition);
  expect(actual.duration, expected.duration);
  expect(actual.speed, expected.speed);
  expect(actual.repeatMode, expected.repeatMode);
  expect(actual.shuffleEnabled, expected.shuffleEnabled);
  expect(actual.failure, expected.failure);
}
