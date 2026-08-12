// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/infrastructure/playback_publication_diff.dart';
import 'package:vi_listen/features/player/infrastructure/player_policies.dart';
import 'package:vi_listen/features/player/infrastructure/player_position_projector.dart';
import '../support/fake_player_clock.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlayerClock clock;
  late PlayerPositionProjector projector;
  late List<PlaybackSnapshot> projections;
  late StreamSubscription<PlaybackSnapshot> subscription;

  setUp(() {
    clock = FakePlayerClock();
    projector = PlayerPositionProjector(clock: clock);
    projections = <PlaybackSnapshot>[];
    subscription = projector.projections.listen(projections.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await projector.dispose();
    await clock.dispose();
  });

  test(
    'coalesces position candidates and emits the latest at a clock tick',
    () async {
      final candidates = [
        _activeSnapshot(position: const Duration(seconds: 11)),
        _activeSnapshot(position: const Duration(seconds: 12)),
        _activeSnapshot(position: const Duration(seconds: 13)),
      ];

      for (final candidate in candidates) {
        projector.onPositionCandidate(candidate);
      }

      await pumpEventQueue();
      expect(projections, isEmpty);

      clock.advance(PlayerPolicies.uiPositionCadence);
      await pumpEventQueue();

      expect(projections, [candidates.last]);

      clock.advance(PlayerPolicies.uiPositionCadence);
      await pumpEventQueue();
      expect(projections, hasLength(1));
    },
  );

  test('does not emit a candidate that equals the last projection', () async {
    final candidate = _activeSnapshot(position: const Duration(seconds: 11));

    projector.onPositionCandidate(candidate);
    clock.advance(PlayerPolicies.uiPositionCadence);
    await pumpEventQueue();

    projector.onPositionCandidate(candidate.copyWith());
    clock.advance(PlayerPolicies.uiPositionCadence);
    await pumpEventQueue();

    expect(projections, [candidate]);
  });

  test('does not emit when a clock tick has no position candidate', () async {
    clock.advance(PlayerPolicies.uiPositionCadence);
    await pumpEventQueue();

    expect(projections, isEmpty);
  });

  test('emits buffering, completed and error snapshots immediately', () async {
    final snapshots = [
      _activeSnapshot(
        processingState: PlaybackProcessingState.buffering,
        position: const Duration(seconds: 11),
      ),
      _activeSnapshot(
        processingState: PlaybackProcessingState.completed,
        playing: false,
        position: const Duration(seconds: 12),
      ),
      _activeSnapshot(
        processingState: PlaybackProcessingState.error,
        playing: false,
        failure: const PlayerFailure(
          code: 'network',
          message: 'Network unavailable.',
          isRecoverable: true,
        ),
        position: const Duration(seconds: 13),
      ),
    ];

    for (final snapshot in snapshots) {
      projector.onImmediate(snapshot);
      await pumpEventQueue();
    }

    expect(projections, snapshots);
  });

  test('immediate snapshots clear a pending candidate', () async {
    final candidate = _activeSnapshot(position: const Duration(seconds: 11));
    final immediate = candidate.copyWith(
      processingState: PlaybackProcessingState.buffering,
    );

    projector.onPositionCandidate(candidate);
    projector.onImmediate(immediate);
    await pumpEventQueue();

    expect(projections, [immediate]);

    clock.advance(PlayerPolicies.uiPositionCadence);
    await pumpEventQueue();
    expect(projections, [immediate]);
  });

  test(
    'preserves item, artwork and queue on a position-only projection',
    () async {
      final item = testPlayerItem(
        id: 'position-track',
        artUri: Uri.parse('https://cdn.example.test/artwork.png'),
      );
      final otherItem = testPlayerItem(id: 'other-track');
      final previous = buildPlaybackSnapshot(
        currentItem: item,
        queue: [item, otherItem],
        currentIndex: 0,
        processingState: PlaybackProcessingState.ready,
        playing: true,
        position: const Duration(seconds: 10),
        bufferedPosition: const Duration(seconds: 20),
        duration: const Duration(minutes: 1),
      );
      final candidate = previous.copyWith(
        position: const Duration(seconds: 11),
      );

      projector.onImmediate(previous);
      projector.onPositionCandidate(candidate);
      clock.advance(PlayerPolicies.uiPositionCadence);
      await pumpEventQueue();

      expect(projections, [previous, candidate]);
      expect(projections.last.currentItem, item);
      expect(projections.last.currentItem?.artUri, item.artUri);
      expect(projections.last.queue, [item, otherItem]);

      final diff = PlaybackPublicationDiff.between(
        previous: previous,
        current: projections.last,
      );
      expect(diff.mediaItemChanged, isFalse);
      expect(diff.queueChanged, isFalse);
    },
  );

  test('dispose is idempotent and does not dispose the clock', () async {
    final firstDispose = projector.dispose();
    final secondDispose = projector.dispose();

    expect(identical(firstDispose, secondDispose), isTrue);

    await firstDispose;
    expect(clock.disposeCount, 0);

    projector.onPositionCandidate(
      _activeSnapshot(position: const Duration(seconds: 11)),
    );
    clock.advance(PlayerPolicies.uiPositionCadence);
    await pumpEventQueue();

    expect(projections, isEmpty);
  });
}

PlaybackSnapshot _activeSnapshot({
  PlaybackProcessingState processingState = PlaybackProcessingState.ready,
  bool playing = true,
  Duration position = Duration.zero,
  PlayerFailure? failure,
}) => buildPlaybackSnapshot(
  currentItem: testPlayerItem(id: 'active-track'),
  queue: [testPlayerItem(id: 'active-track')],
  currentIndex: 0,
  processingState: processingState,
  playing: playing,
  position: position,
  duration: const Duration(minutes: 1),
  failure: failure,
);
