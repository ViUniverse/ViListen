// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';

void main() {
  group('PlaybackSnapshot derived values', () {
    test('guards zero and negative duration as unknown', () {
      final zeroDuration = _snapshot(
        position: const Duration(seconds: 10),
        duration: Duration.zero,
      );
      final negativeDuration = _snapshot(
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: -1),
      );

      expect(zeroDuration.progress, 0.0);
      expect(zeroDuration.remaining, Duration.zero);
      expect(negativeDuration.progress, 0.0);
      expect(negativeDuration.remaining, Duration.zero);
    });

    test('clamps negative and over-duration positions', () {
      final negativePosition = _snapshot(
        position: const Duration(seconds: -1),
        duration: const Duration(seconds: 10),
      );
      final overDurationPosition = _snapshot(
        position: const Duration(seconds: 12),
        duration: const Duration(seconds: 10),
      );
      final regularPosition = _snapshot(
        position: const Duration(seconds: 3),
        duration: const Duration(seconds: 10),
      );

      expect(negativePosition.progress, 0.0);
      expect(negativePosition.remaining, const Duration(seconds: 10));
      expect(overDurationPosition.progress, 1.0);
      expect(overDurationPosition.remaining, Duration.zero);
      expect(regularPosition.progress, 0.3);
      expect(regularPosition.remaining, const Duration(seconds: 7));
    });

    test('reports buffering independently from playing', () {
      final bufferingWhilePlaying = _snapshot(
        processingState: PlaybackProcessingState.buffering,
        playing: true,
      );
      final bufferingWhilePaused = _snapshot(
        processingState: PlaybackProcessingState.buffering,
        playing: false,
      );

      expect(bufferingWhilePlaying.isBuffering, isTrue);
      expect(bufferingWhilePlaying.isAudible, isFalse);
      expect(bufferingWhilePaused.isBuffering, isTrue);
      expect(bufferingWhilePaused.isAudible, isFalse);
    });

    test('is audible only when ready and playing', () {
      final readyWhilePlaying = _snapshot(
        processingState: PlaybackProcessingState.ready,
        playing: true,
      );
      final readyWhilePaused = _snapshot(
        processingState: PlaybackProcessingState.ready,
        playing: false,
      );

      expect(readyWhilePlaying.isBuffering, isFalse);
      expect(readyWhilePlaying.isAudible, isTrue);
      expect(readyWhilePaused.isAudible, isFalse);
    });

    test('reports queue boundaries only for a valid current index', () {
      final first = _item('first');
      final middle = _item('middle');
      final last = _item('last');

      final empty = _snapshot();
      final nullIndex = _snapshot(queue: [first], currentIndex: null);
      final firstIndex = _snapshot(
        queue: [first, middle, last],
        currentIndex: 0,
      );
      final middleIndex = _snapshot(
        queue: [first, middle, last],
        currentIndex: 1,
      );
      final lastIndex = _snapshot(
        queue: [first, middle, last],
        currentIndex: 2,
      );
      final negativeIndex = _snapshot(
        queue: [first, middle, last],
        currentIndex: -1,
      );
      final outOfBoundsIndex = _snapshot(
        queue: [first, middle, last],
        currentIndex: 3,
      );

      expect(empty.hasNext, isFalse);
      expect(empty.hasPrevious, isFalse);
      expect(nullIndex.hasNext, isFalse);
      expect(nullIndex.hasPrevious, isFalse);
      expect(firstIndex.hasNext, isTrue);
      expect(firstIndex.hasPrevious, isFalse);
      expect(middleIndex.hasNext, isTrue);
      expect(middleIndex.hasPrevious, isTrue);
      expect(lastIndex.hasNext, isFalse);
      expect(lastIndex.hasPrevious, isTrue);
      expect(negativeIndex.hasNext, isFalse);
      expect(negativeIndex.hasPrevious, isFalse);
      expect(outOfBoundsIndex.hasNext, isFalse);
      expect(outOfBoundsIndex.hasPrevious, isFalse);
    });

    test('completed keeps the snapshot metadata available', () {
      final item = _item('completed');
      final failure = const PlayerFailure(
        code: 'metadata',
        message: 'Metadata is retained.',
        isRecoverable: false,
        itemId: 'completed',
      );
      final snapshot = _snapshot(
        currentItem: item,
        queue: [item],
        currentIndex: 0,
        processingState: PlaybackProcessingState.completed,
        position: const Duration(seconds: 10),
        bufferedPosition: const Duration(seconds: 10),
        duration: const Duration(seconds: 10),
        speed: 1.5,
        repeatMode: PlayerRepeatMode.all,
        shuffleEnabled: true,
        failure: failure,
      );

      expect(snapshot.isCompleted, isTrue);
      expect(snapshot.currentItem, item);
      expect(snapshot.queue, [item]);
      expect(snapshot.currentIndex, 0);
      expect(snapshot.position, const Duration(seconds: 10));
      expect(snapshot.bufferedPosition, const Duration(seconds: 10));
      expect(snapshot.duration, const Duration(seconds: 10));
      expect(snapshot.progress, 1.0);
      expect(snapshot.remaining, Duration.zero);
      expect(snapshot.speed, 1.5);
      expect(snapshot.repeatMode, PlayerRepeatMode.all);
      expect(snapshot.shuffleEnabled, isTrue);
      expect(snapshot.failure, failure);
    });
  });
}

PlaybackSnapshot _snapshot({
  PlayerItem? currentItem,
  List<PlayerItem> queue = const <PlayerItem>[],
  int? currentIndex,
  PlaybackProcessingState processingState = PlaybackProcessingState.idle,
  bool playing = false,
  Duration position = Duration.zero,
  Duration bufferedPosition = Duration.zero,
  Duration duration = Duration.zero,
  double speed = 1.0,
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off,
  bool shuffleEnabled = false,
  PlayerFailure? failure,
}) => PlaybackSnapshot(
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
  failure: failure,
);

PlayerItem _item(String id) => PlayerItem(
  id: id,
  audioUri: Uri.parse('https://cdn.example.test/$id.mp3'),
  title: 'Episode $id',
  artist: 'The Artist',
);
