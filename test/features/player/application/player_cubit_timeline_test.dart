// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
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

  test('seekTo forwards the exact Duration to the gateway', () async {
    final requestedPosition = const Duration(microseconds: 1_234_567);

    await cubit.seekTo(requestedPosition);

    expect(gateway.callCountFor('seek'), 1);
    expect(gateway.commands.single.arguments, {'position': requestedPosition});
    expect(cubit.state.playback, same(PlaybackSnapshot.idle));
  });

  test('skip commands forward exactly minus and plus ten seconds', () async {
    await cubit.skipBackward();
    await cubit.skipForward();

    expect(gateway.commands.map((command) => command.name), [
      'skipBy',
      'skipBy',
    ]);
    expect(gateway.commands[0].arguments, {
      'offset': const Duration(seconds: -10),
    });
    expect(gateway.commands[1].arguments, {
      'offset': const Duration(seconds: 10),
    });
    expect(gateway.callCountFor('next'), 0);
    expect(gateway.callCountFor('previous'), 0);
    expect(gateway.callCountFor('seek'), 0);
  });

  test('stop keeps confirmed state until the idle snapshot arrives', () async {
    final item = testPlayerItem();
    final active = buildPlaybackSnapshot(
      currentItem: item,
      queue: [item],
      currentIndex: 0,
      processingState: PlaybackProcessingState.ready,
      playing: true,
      position: const Duration(seconds: 42),
      duration: const Duration(minutes: 2),
    );
    gateway.emit(active);
    await _flushStreamEvents();

    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.stop();

    expect(gateway.callCountFor('stop'), 1);
    expect(cubit.state.playback, same(active));
    expect(emittedStates, isEmpty);

    gateway.emit(PlaybackSnapshot.idle);
    await _flushStreamEvents();

    expect(cubit.state.playback, same(PlaybackSnapshot.idle));
    expect(emittedStates, [PlayerState.fromSnapshot(PlaybackSnapshot.idle)]);
  });

  test(
    'stop clears a pending play intent before the next item toggle',
    () async {
      final previousItem = testPlayerItem(id: 'before-stop');
      final previousPaused = buildPlaybackSnapshot(
        currentItem: previousItem,
        queue: [previousItem],
        currentIndex: 0,
        processingState: PlaybackProcessingState.ready,
      );
      gateway.emit(previousPaused);
      await _flushStreamEvents();

      await cubit.togglePlayback();
      await cubit.stop();
      gateway.emit(PlaybackSnapshot.idle);
      await _flushStreamEvents();

      final nextItem = testPlayerItem(id: 'after-stop');
      await cubit.open(nextItem, autoplay: false);
      final nextPaused = buildPlaybackSnapshot(
        currentItem: nextItem,
        queue: [nextItem],
        currentIndex: 0,
        processingState: PlaybackProcessingState.ready,
      );
      gateway.emit(nextPaused);
      await _flushStreamEvents();

      await cubit.togglePlayback();

      expect(gateway.commands.map((command) => command.name), [
        'play',
        'stop',
        'loadQueue',
        'play',
      ]);
      expect(gateway.callCountFor('pause'), 0);
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
