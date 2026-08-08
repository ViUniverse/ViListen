// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';

void main() {
  group('PlaybackSnapshot', () {
    test('idle has the canonical baseline values', () {
      final idle = PlaybackSnapshot.idle;

      expect(idle.currentItem, isNull);
      expect(idle.queue, isEmpty);
      expect(idle.currentIndex, isNull);
      expect(idle.processingState, PlaybackProcessingState.idle);
      expect(idle.playing, isFalse);
      expect(idle.position, Duration.zero);
      expect(idle.bufferedPosition, Duration.zero);
      expect(idle.duration, Duration.zero);
      expect(idle.speed, 1.0);
      expect(idle.repeatMode, PlayerRepeatMode.off);
      expect(idle.shuffleEnabled, isFalse);
      expect(idle.failure, isNull);
      expect(PlaybackSnapshot.idle, same(PlaybackSnapshot.idle));
    });

    test('retains all fields and uses value equality and hashCode', () {
      final first = _item(id: 'track-1');
      final second = _item(id: 'track-2');
      final failure = _failure();
      final snapshot = _snapshot(
        currentItem: second,
        queue: [first, second],
        currentIndex: 1,
        processingState: PlaybackProcessingState.error,
        playing: true,
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(seconds: 20),
        duration: const Duration(minutes: 2),
        speed: 1.5,
        repeatMode: PlayerRepeatMode.all,
        shuffleEnabled: true,
        failure: failure,
      );
      final sameValue = _snapshot(
        currentItem: _item(id: 'track-2'),
        queue: [
          _item(id: 'track-1'),
          _item(id: 'track-2'),
        ],
        currentIndex: 1,
        processingState: PlaybackProcessingState.error,
        playing: true,
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(seconds: 20),
        duration: const Duration(minutes: 2),
        speed: 1.5,
        repeatMode: PlayerRepeatMode.all,
        shuffleEnabled: true,
        failure: const PlayerFailure(
          code: 'network',
          message: 'Network unavailable.',
          isRecoverable: true,
          itemId: 'track-2',
        ),
      );

      expect(snapshot, sameValue);
      expect(snapshot.hashCode, sameValue.hashCode);
      expect(snapshot, isNot(snapshot.copyWith(currentItem: first)));
      expect(snapshot, isNot(snapshot.copyWith(queue: [second, first])));
      expect(snapshot, isNot(snapshot.copyWith(currentIndex: 0)));
      expect(
        snapshot,
        isNot(
          snapshot.copyWith(processingState: PlaybackProcessingState.ready),
        ),
      );
      expect(snapshot, isNot(snapshot.copyWith(playing: false)));
      expect(
        snapshot,
        isNot(snapshot.copyWith(position: const Duration(seconds: 13))),
      );
      expect(
        snapshot,
        isNot(snapshot.copyWith(bufferedPosition: const Duration(seconds: 21))),
      );
      expect(
        snapshot,
        isNot(snapshot.copyWith(duration: const Duration(minutes: 3))),
      );
      expect(snapshot, isNot(snapshot.copyWith(speed: 2.0)));
      expect(
        snapshot,
        isNot(snapshot.copyWith(repeatMode: PlayerRepeatMode.one)),
      );
      expect(snapshot, isNot(snapshot.copyWith(shuffleEnabled: false)));
      expect(snapshot, isNot(snapshot.copyWith(failure: null)));
    });

    test('copyWith changes one field without dropping the others', () {
      final snapshot = _snapshot(
        currentItem: _item(),
        queue: [_item()],
        currentIndex: 0,
        processingState: PlaybackProcessingState.ready,
        playing: true,
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(seconds: 20),
        duration: const Duration(minutes: 2),
        speed: 1.0,
        repeatMode: PlayerRepeatMode.off,
        shuffleEnabled: false,
        failure: null,
      );

      final copy = snapshot.copyWith(speed: 1.5);

      expect(copy.speed, 1.5);
      expect(copy.currentItem, snapshot.currentItem);
      expect(copy.queue, snapshot.queue);
      expect(copy.currentIndex, snapshot.currentIndex);
      expect(copy.processingState, snapshot.processingState);
      expect(copy.playing, snapshot.playing);
      expect(copy.position, snapshot.position);
      expect(copy.bufferedPosition, snapshot.bufferedPosition);
      expect(copy.duration, snapshot.duration);
      expect(copy.repeatMode, snapshot.repeatMode);
      expect(copy.shuffleEnabled, snapshot.shuffleEnabled);
      expect(copy.failure, snapshot.failure);
    });

    test('copyWith can clear nullable fields', () {
      final snapshot = _snapshot(
        currentItem: _item(),
        currentIndex: 0,
        failure: _failure(),
      );

      final copy = snapshot.copyWith(
        currentItem: null,
        currentIndex: null,
        failure: null,
      );

      expect(copy.currentItem, isNull);
      expect(copy.currentIndex, isNull);
      expect(copy.failure, isNull);
    });

    test('defensively copies and protects the queue', () {
      final first = _item(id: 'track-1');
      final second = _item(id: 'track-2');
      final inputQueue = <PlayerItem>[first];
      final snapshot = _snapshot(queue: inputQueue);

      inputQueue.add(second);

      expect(snapshot.queue, [first]);
      expect(() => snapshot.queue.add(second), throwsUnsupportedError);
    });

    test('does not infer engine transitions or normalize failure state', () {
      final snapshot = _snapshot(
        processingState: PlaybackProcessingState.ready,
        playing: true,
        failure: null,
      );

      final buffering = snapshot.copyWith(
        processingState: PlaybackProcessingState.buffering,
      );
      final failed = snapshot.copyWith(
        processingState: PlaybackProcessingState.error,
      );
      final withFailure = snapshot.copyWith(failure: _failure());

      expect(buffering.playing, isTrue);
      expect(buffering.failure, isNull);
      expect(failed.playing, isTrue);
      expect(failed.failure, isNull);
      expect(withFailure.processingState, PlaybackProcessingState.ready);
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

PlayerItem _item({String id = 'track-1'}) => PlayerItem(
  id: id,
  audioUri: Uri.parse('https://cdn.example.test/$id.mp3'),
  title: 'Episode $id',
  artist: 'The Artist',
);

PlayerFailure _failure() => const PlayerFailure(
  code: 'network',
  message: 'Network unavailable.',
  isRecoverable: true,
  itemId: 'track-2',
);
