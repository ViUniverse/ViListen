import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
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

  test('next and previous each delegate exactly one gateway call', () async {
    await cubit.next();
    await cubit.previous();

    expect(gateway.callCountFor('next'), 1);
    expect(gateway.callCountFor('previous'), 1);
    expect(gateway.commands.map((command) => command.name), [
      'next',
      'previous',
    ]);
    expect(cubit.state.playback, same(PlaybackSnapshot.idle));
  });

  test(
    'next at the queue boundary does not infer a new current item',
    () async {
      final first = testPlayerItem(id: 'track-1');
      final last = testPlayerItem(id: 'track-2');
      final boundary = buildPlaybackSnapshot(
        currentItem: last,
        queue: [first, last],
        currentIndex: 1,
        processingState: PlaybackProcessingState.ready,
      );
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(initialSnapshot: boundary);
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);
      await _flushStreamEvents();

      await cubit.next();

      expect(gateway.callCountFor('next'), 1);
      expect(cubit.state.playback, same(boundary));
      expect(cubit.state.currentItem, same(last));
      expect(cubit.state.playback.queue, [first, last]);
      expect(cubit.state.playback.currentIndex, 1);
    },
  );

  test(
    'previous at the queue boundary does not infer a new current item',
    () async {
      final first = testPlayerItem(id: 'track-1');
      final last = testPlayerItem(id: 'track-2');
      final boundary = buildPlaybackSnapshot(
        currentItem: first,
        queue: [first, last],
        currentIndex: 0,
        processingState: PlaybackProcessingState.ready,
      );
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(initialSnapshot: boundary);
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);
      await _flushStreamEvents();

      await cubit.previous();

      expect(gateway.callCountFor('previous'), 1);
      expect(cubit.state.playback, same(boundary));
      expect(cubit.state.currentItem, same(first));
      expect(cubit.state.playback.queue, [first, last]);
      expect(cubit.state.playback.currentIndex, 0);
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
