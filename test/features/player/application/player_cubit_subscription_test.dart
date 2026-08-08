// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import '../support/fake_playback_gateway.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackGateway gateway;
  late PlayerCubit cubit;

  setUp(() {
    gateway = FakePlaybackGateway();
    cubit = PlayerCubit(gateway);
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await gateway.dispose();
  });

  test('starts idle and receives snapshots from the gateway', () async {
    expect(cubit.state, PlayerState.fromSnapshot(PlaybackSnapshot.idle));

    final snapshot = buildPlaybackSnapshot(
      currentItem: testPlayerItem(),
      processingState: PlaybackProcessingState.loading,
    );
    gateway.emit(snapshot);
    await _flushStreamEvents();

    expect(cubit.state.playback, same(snapshot));
  });

  test(
    'maps loading, ready, buffering, completed, and error snapshots',
    () async {
      final item = testPlayerItem();
      const failure = PlayerFailure(
        code: 'network',
        message: 'Network unavailable.',
        isRecoverable: true,
        itemId: 'track-1',
      );
      final snapshots = <PlaybackSnapshot>[
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.loading,
        ),
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.ready,
          playing: true,
        ),
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.buffering,
          playing: true,
        ),
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.completed,
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 1),
        ),
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.error,
          failure: failure,
        ),
      ];
      final states = <PlayerState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);

      for (final snapshot in snapshots) {
        gateway.emit(snapshot);
        await _flushStreamEvents();
      }

      expect(states.map((state) => state.playback.processingState), [
        PlaybackProcessingState.loading,
        PlaybackProcessingState.ready,
        PlaybackProcessingState.buffering,
        PlaybackProcessingState.completed,
        PlaybackProcessingState.error,
      ]);
      expect(
        states.map((state) => state.currentItem),
        everyElement(same(item)),
      );
      expect(states[1].playing, isTrue);
      expect(states[2].isBuffering, isTrue);
      expect(states[3].isCompleted, isTrue);
      expect(states.last.failure, same(failure));
    },
  );

  test('does not emit a state for a duplicate snapshot', () async {
    final snapshot = buildPlaybackSnapshot(
      currentItem: testPlayerItem(),
      processingState: PlaybackProcessingState.ready,
      playing: true,
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 1),
    );
    final sameValueSnapshot = buildPlaybackSnapshot(
      currentItem: testPlayerItem(),
      processingState: PlaybackProcessingState.ready,
      playing: true,
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 1),
    );
    final states = <PlayerState>[];
    final subscription = cubit.stream.listen(states.add);
    addTearDown(subscription.cancel);

    gateway.emit(snapshot);
    await _flushStreamEvents();
    gateway.emit(sameValueSnapshot);
    await _flushStreamEvents();

    expect(states, [PlayerState.fromSnapshot(snapshot)]);
  });

  test('changes position only when the gateway emits a new snapshot', () async {
    final first = buildPlaybackSnapshot(
      currentItem: testPlayerItem(),
      processingState: PlaybackProcessingState.ready,
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 1),
    );
    final second = first.copyWith(position: const Duration(seconds: 20));
    final positions = <Duration>[];
    final subscription = cubit.stream.listen(
      (state) => positions.add(state.position),
    );
    addTearDown(subscription.cancel);

    gateway.emit(first);
    await _flushStreamEvents();
    expect(cubit.state.position, const Duration(seconds: 10));

    await _flushStreamEvents();
    expect(cubit.state.position, const Duration(seconds: 10));

    gateway.emit(second);
    await _flushStreamEvents();

    expect(cubit.state.position, const Duration(seconds: 20));
    expect(positions, [
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ]);
  });

  test('cancels the snapshot subscription when closed', () async {
    final first = buildPlaybackSnapshot(
      currentItem: testPlayerItem(),
      processingState: PlaybackProcessingState.ready,
    );
    gateway.emit(first);
    await _flushStreamEvents();

    await cubit.close();

    gateway.emit(first.copyWith(position: const Duration(seconds: 5)));
    await _flushStreamEvents();

    expect(cubit.isClosed, isTrue);
    expect(cubit.state.playback, same(first));
  });
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
