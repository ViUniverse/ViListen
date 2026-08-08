// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';

void main() {
  group('PlayerState', () {
    test('wraps exactly one snapshot through fromSnapshot', () {
      final snapshot = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.ready,
        playing: true,
      );

      final state = PlayerState.fromSnapshot(snapshot);

      expect(state.playback, same(snapshot));
    });

    test('projects convenience getters from the snapshot', () {
      final item = testPlayerItem();
      const failure = PlayerFailure(
        code: 'network',
        message: 'Network unavailable.',
        isRecoverable: true,
        itemId: 'track-1',
      );
      final snapshot = buildPlaybackSnapshot(
        currentItem: item,
        processingState: PlaybackProcessingState.buffering,
        playing: true,
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 60),
        failure: failure,
      );
      final state = PlayerState.fromSnapshot(snapshot);

      expect(state.currentItem, same(snapshot.currentItem));
      expect(state.playing, snapshot.playing);
      expect(state.isBuffering, snapshot.isBuffering);
      expect(state.isCompleted, snapshot.isCompleted);
      expect(state.progress, snapshot.progress);
      expect(state.position, snapshot.position);
      expect(state.duration, snapshot.duration);
      expect(state.failure, same(snapshot.failure));
    });

    test('uses snapshot value equality', () {
      final firstSnapshot = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.ready,
        playing: true,
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 2),
      );
      final sameValueSnapshot = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.ready,
        playing: true,
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 2),
      );
      final changedSnapshot = firstSnapshot.copyWith(
        position: const Duration(seconds: 11),
      );

      final firstState = PlayerState.fromSnapshot(firstSnapshot);
      final sameValueState = PlayerState.fromSnapshot(sameValueSnapshot);
      final changedState = PlayerState.fromSnapshot(changedSnapshot);

      expect(firstState, sameValueState);
      expect(firstState.hashCode, sameValueState.hashCode);
      expect(firstState, isNot(changedState));
    });

    for (final processingState in [
      PlaybackProcessingState.buffering,
      PlaybackProcessingState.completed,
      PlaybackProcessingState.error,
    ]) {
      test('$processingState keeps the current item', () {
        final item = testPlayerItem();
        final snapshot = buildPlaybackSnapshot(
          currentItem: item,
          queue: [item],
          currentIndex: 0,
          processingState: processingState,
          failure: processingState == PlaybackProcessingState.error
              ? const PlayerFailure(
                  code: 'network',
                  message: 'Network unavailable.',
                  isRecoverable: true,
                  itemId: 'track-1',
                )
              : null,
        );

        final state = PlayerState.fromSnapshot(snapshot);

        expect(state.currentItem, same(item));
        expect(state.playback.currentItem, same(item));
      });
    }
  });
}
