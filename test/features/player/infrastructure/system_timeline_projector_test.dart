// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/player_policies.dart';
import 'package:vi_listen/features/player/infrastructure/system_timeline_projector.dart';
import '../support/fake_player_clock.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlayerClock clock;
  late SystemTimelineProjector projector;
  late List<PlaybackSnapshot> projections;

  setUp(() {
    clock = FakePlayerClock();
    projector = SystemTimelineProjector(clock: clock);
    projections = <PlaybackSnapshot>[];
    projector.projections.listen(projections.add);
  });

  tearDown(() async {
    await projector.dispose();
    await clock.dispose();
  });

  test('coalesces position candidates until the OS cadence', () async {
    final candidates = [
      _snapshot(position: const Duration(seconds: 1)),
      _snapshot(position: const Duration(seconds: 2)),
      _snapshot(position: const Duration(seconds: 3)),
    ];

    for (final candidate in candidates) {
      projector.onPositionCandidate(candidate);
      clock.advance(PlayerPolicies.uiPositionCadence);
    }
    await pumpEventQueue();

    expect(projections, isEmpty);

    clock.advance(
      PlayerPolicies.osPositionCadence - PlayerPolicies.uiPositionCadence * 3,
    );
    await pumpEventQueue();

    expect(projections, [candidates.last]);
  });

  test('immediate snapshots bypass cadence and clear candidates', () async {
    projector.onPositionCandidate(
      _snapshot(position: const Duration(seconds: 1)),
    );
    final immediate = _snapshot(
      processingState: PlaybackProcessingState.buffering,
      position: const Duration(seconds: 2),
    );

    projector.onImmediate(immediate);
    await pumpEventQueue();

    expect(projections, [immediate]);

    clock.advance(PlayerPolicies.osPositionCadence);
    await pumpEventQueue();
    expect(projections, [immediate]);
  });

  test('dispose is idempotent and does not dispose the clock', () async {
    final firstDispose = projector.dispose();
    final secondDispose = projector.dispose();

    expect(identical(firstDispose, secondDispose), isTrue);
    await firstDispose;
    expect(clock.disposeCount, 0);
  });
}

PlaybackSnapshot _snapshot({
  PlaybackProcessingState processingState = PlaybackProcessingState.ready,
  Duration position = Duration.zero,
}) {
  final item = testPlayerItem(id: 'timeline-track');
  return buildPlaybackSnapshot(
    currentItem: item,
    queue: [item],
    currentIndex: 0,
    processingState: processingState,
    playing: true,
    position: position,
    duration: const Duration(minutes: 1),
  );
}
