import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_command_failure.dart';
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

  test(
    'retry delegates exactly once and does not mutate state optimistically',
    () async {
      final failed = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.error,
      );
      gateway.emit(failed);
      await _flushStreamEvents();

      final stateBeforeRetry = cubit.state;
      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await cubit.retry();

      expect(gateway.callCountFor('retry'), 1);
      expect(cubit.state, same(stateBeforeRetry));
      expect(emittedStates, isEmpty);

      final recovered = failed.copyWith(
        processingState: PlaybackProcessingState.ready,
        failure: null,
      );
      gateway.emit(recovered);
      await _flushStreamEvents();

      expect(cubit.state.playback, same(recovered));
      expect(emittedStates, [PlayerState.fromSnapshot(recovered)]);
    },
  );

  test('each user retry call delegates once', () async {
    await cubit.retry();
    await cubit.retry();

    expect(gateway.callCountFor('retry'), 2);
    expect(gateway.commands.map((command) => command.name), ['retry', 'retry']);
  });

  test(
    'propagates retryUnavailable without changing confirmed state',
    () async {
      const retryUnavailable = PlayerCommandFailure(
        code: 'retryUnavailable',
        message: 'Retry is unavailable.',
        command: 'retry',
      );
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(
        commandBehaviors: <String, FakeCommandBehavior>{
          'retry': (_) => throw retryUnavailable,
        },
      );
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);

      final stateBeforeRetry = cubit.state;
      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await expectLater(cubit.retry(), throwsA(same(retryUnavailable)));

      expect(gateway.callCountFor('retry'), 1);
      expect(cubit.state, same(stateBeforeRetry));
      expect(emittedStates, isEmpty);
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
