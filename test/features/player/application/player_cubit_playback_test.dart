import 'dart:async';

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

  test('play and pause each delegate exactly one gateway call', () async {
    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.play();
    await cubit.pause();

    expect(gateway.callCountFor('play'), 1);
    expect(gateway.callCountFor('pause'), 1);
    expect(cubit.state.playback, PlaybackSnapshot.idle);
    expect(emittedStates, isEmpty);
  });

  test('toggle does not change state before the engine snapshot', () async {
    final paused = buildPlaybackSnapshot(
      currentItem: testPlayerItem(),
      processingState: PlaybackProcessingState.ready,
    );
    gateway.emit(paused);
    await _flushStreamEvents();

    final stateBeforeToggle = cubit.state;
    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.togglePlayback();

    expect(gateway.callCountFor('play'), 1);
    expect(cubit.state, same(stateBeforeToggle));
    expect(emittedStates, isEmpty);

    final playing = paused.copyWith(playing: true);
    gateway.emit(playing);
    await _flushStreamEvents();

    expect(cubit.state.playback, same(playing));
    expect(emittedStates, [PlayerState.fromSnapshot(playing)]);
  });

  test(
    'gateway error keeps the confirmed state and clears the intent',
    () async {
      final failure = StateError('playback engine failed');
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(
        commandBehaviors: <String, FakeCommandBehavior>{
          'play': (_) => throw failure,
        },
      );
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);

      final stateBeforeToggle = cubit.state;
      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await expectLater(cubit.togglePlayback(), throwsA(same(failure)));

      expect(cubit.state, same(stateBeforeToggle));
      expect(emittedStates, isEmpty);

      await expectLater(cubit.togglePlayback(), throwsA(same(failure)));
      expect(gateway.callCountFor('play'), 2);
      expect(gateway.callCountFor('pause'), 0);
    },
  );

  test(
    'double toggle keeps last desired intent before a snapshot confirmation',
    () async {
      final paused = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.ready,
      );
      gateway.emit(paused);
      await _flushStreamEvents();

      final stateBeforeToggle = cubit.state;
      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await cubit.togglePlayback();
      await cubit.togglePlayback();

      expect(gateway.commands.map((command) => command.name), [
        'play',
        'pause',
      ]);
      expect(cubit.state, same(stateBeforeToggle));
      expect(cubit.state.playing, isFalse);
      expect(emittedStates, isEmpty);
    },
  );

  test(
    'interim position snapshot does not clear a pending pause intent',
    () async {
      final playing = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.ready,
        playing: true,
        position: const Duration(seconds: 10),
      );
      gateway.emit(playing);
      await _flushStreamEvents();

      final pauseCompletion = Completer<void>();
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(
        initialSnapshot: playing,
        commandBehaviors: <String, FakeCommandBehavior>{
          'pause': (_) => pauseCompletion.future,
        },
      );
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);
      await _flushStreamEvents();

      final pauseFuture = cubit.togglePlayback();
      await _flushStreamEvents();
      expect(gateway.commands.map((command) => command.name), ['pause']);

      gateway.emit(playing.copyWith(position: const Duration(seconds: 20)));
      await _flushStreamEvents();

      final playFuture = cubit.togglePlayback();
      await _flushStreamEvents();

      expect(gateway.commands.map((command) => command.name), [
        'pause',
        'play',
      ]);

      pauseCompletion.complete();
      await pauseFuture;
      await playFuture;
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
