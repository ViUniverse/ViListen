// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/playback_publication_diff.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';

void main() {
  final itemA = testPlayerItem(id: 'track-a');
  final itemB = testPlayerItem(id: 'track-b');
  final base = buildPlaybackSnapshot(
    currentItem: itemA,
    queue: [itemA, itemB],
    currentIndex: 0,
    processingState: PlaybackProcessingState.ready,
    playing: true,
    position: const Duration(seconds: 10),
    bufferedPosition: const Duration(seconds: 20),
    duration: const Duration(minutes: 1),
  );

  PlaybackPublicationDiff diffFor(PlaybackSnapshot current) =>
      PlaybackPublicationDiff.between(previous: base, current: current);

  test('skips an identical snapshot', () {
    final result = diffFor(base.copyWith());

    expect(result.isDuplicate, isTrue);
    expect(result.snapshotChanged, isFalse);
    expect(result.playbackStateChanged, isFalse);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test('fresh equal queue values do not create a queue publication', () {
    final clonedA = itemA.copyWith();
    final clonedB = itemB.copyWith();
    final result = diffFor(
      base.copyWith(
        position: const Duration(seconds: 11),
        currentItem: clonedA,
        queue: [clonedA, clonedB],
      ),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test('position-only change affects domain and OS state only', () {
    final result = diffFor(
      base.copyWith(position: const Duration(seconds: 11)),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test('buffered position-only change does not publish metadata or queue', () {
    final result = diffFor(
      base.copyWith(bufferedPosition: const Duration(seconds: 21)),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test(
    'play, pause and buffering changes do not publish metadata or queue',
    () {
      final cases = [
        base.copyWith(playing: false),
        base.copyWith(processingState: PlaybackProcessingState.buffering),
        base.copyWith(speed: 1.25),
        base.copyWith(repeatMode: PlayerRepeatMode.all),
        base.copyWith(shuffleEnabled: true),
      ];

      for (final current in cases) {
        final result = diffFor(current);

        expect(result.snapshotChanged, isTrue);
        expect(result.playbackStateChanged, isTrue);
        expect(result.mediaItemChanged, isFalse);
        expect(result.queueChanged, isFalse);
      }
    },
  );

  test('current item change triggers media item and OS state', () {
    final result = diffFor(base.copyWith(currentItem: itemB, currentIndex: 1));

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isTrue);
    expect(result.queueChanged, isFalse);
  });

  test('item metadata change with the same ID triggers its publication', () {
    final updatedItem = itemA.copyWith(title: 'Updated title');
    final current = base.copyWith(
      currentItem: updatedItem,
      queue: [updatedItem, itemB],
    );
    final result = diffFor(current);

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isFalse);
    expect(result.mediaItemChanged, isTrue);
    expect(result.queueChanged, isTrue);
  });

  test('domain-only complex extras do not trigger OS metadata or queue', () {
    final updatedItem = itemA.copyWith(
      extras: <String, Object?>{
        'transcript': ['one', 'two', 'three'],
      },
    );
    final current = base.copyWith(
      currentItem: updatedItem,
      queue: [updatedItem, itemB],
    );
    final result = diffFor(current);

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isFalse);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test('scalar extras and audio URI changes trigger metadata and queue', () {
    final scalarExtraItem = itemA.copyWith(
      extras: <String, Object?>{'chapter': 2},
    );
    final uriItem = itemA.copyWith(
      audioUri: Uri.parse('https://cdn.example.test/audio/updated.mp3'),
    );

    for (final updatedItem in [scalarExtraItem, uriItem]) {
      final result = diffFor(
        base.copyWith(currentItem: updatedItem, queue: [updatedItem, itemB]),
      );

      expect(result.mediaItemChanged, isTrue);
      expect(result.queueChanged, isTrue);
    }
  });

  test('reserved audioUri extra alone does not change OS payload', () {
    final updatedItem = itemA.copyWith(
      extras: const <String, Object?>{'audioUri': 'should-be-overwritten'},
    );
    final result = diffFor(
      base.copyWith(currentItem: updatedItem, queue: [updatedItem, itemB]),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test('artwork change with the same ID triggers metadata and queue', () {
    final updatedItem = itemA.copyWith(
      artUri: Uri.parse('https://cdn.example.test/art-updated.png'),
    );
    final result = diffFor(
      base.copyWith(currentItem: updatedItem, queue: [updatedItem, itemB]),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.mediaItemChanged, isTrue);
    expect(result.queueChanged, isTrue);
  });

  test('active to canonical idle changes every outward classification', () {
    final result = PlaybackPublicationDiff.between(
      previous: base,
      current: PlaybackSnapshot.idle,
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isTrue);
    expect(result.queueChanged, isTrue);
  });

  test('queue order change triggers queue while preserving current item', () {
    final result = diffFor(
      base.copyWith(queue: [itemB, itemA], currentIndex: 1),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isTrue);
  });

  test('non-current queue item metadata change triggers queue only', () {
    final updatedItem = itemB.copyWith(title: 'Updated queue title');
    final result = diffFor(base.copyWith(queue: [itemA, updatedItem]));

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isFalse);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isTrue);
  });

  test('duration becoming known changes OS controls, not media item', () {
    final unknownDuration = base.copyWith(
      duration: Duration.zero,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
    );
    final knownDuration = unknownDuration.copyWith(
      duration: const Duration(seconds: 90),
    );

    final result = PlaybackPublicationDiff.between(
      previous: unknownDuration,
      current: knownDuration,
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isTrue);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test('known duration change does not change a stable OS payload', () {
    final result = diffFor(
      base.copyWith(duration: const Duration(seconds: 61)),
    );

    expect(result.snapshotChanged, isTrue);
    expect(result.playbackStateChanged, isFalse);
    expect(result.mediaItemChanged, isFalse);
    expect(result.queueChanged, isFalse);
  });

  test(
    'failure message changes only the domain when OS error payload is same',
    () {
      const firstFailure = PlayerFailure(
        code: 'network',
        message: 'first raw network error',
        isRecoverable: true,
        itemId: 'track-a',
      );
      const secondFailure = PlayerFailure(
        code: 'network',
        message: 'second raw network error',
        isRecoverable: true,
        itemId: 'track-a',
      );
      final previous = base.copyWith(
        processingState: PlaybackProcessingState.error,
        playing: false,
        failure: firstFailure,
      );
      final current = previous.copyWith(failure: secondFailure);

      final result = PlaybackPublicationDiff.between(
        previous: previous,
        current: current,
      );

      expect(result.snapshotChanged, isTrue);
      expect(result.playbackStateChanged, isFalse);
      expect(result.mediaItemChanged, isFalse);
      expect(result.queueChanged, isFalse);
    },
  );
}
