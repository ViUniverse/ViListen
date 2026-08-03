import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
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

  test('open delegates one item at index zero with autoplay', () async {
    final item = testPlayerItem();
    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.open(item, autoplay: false);

    expect(gateway.callCountFor('loadQueue'), 1);
    expect(gateway.commands.single.arguments, {
      'items': [item],
      'initialIndex': 0,
      'autoplay': false,
    });
    expect(cubit.state.playback, PlaybackSnapshot.idle);
    expect(emittedStates, isEmpty);
  });

  test('openQueue delegates items, index, and autoplay unchanged', () async {
    final items = [
      testPlayerItem(id: 'track-1'),
      testPlayerItem(id: 'track-2'),
      testPlayerItem(id: 'track-3'),
    ];
    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.openQueue(items, initialIndex: 2, autoplay: false);

    expect(gateway.callCountFor('loadQueue'), 1);
    expect(gateway.commands.single.arguments, {
      'items': items,
      'initialIndex': 2,
      'autoplay': false,
    });
    expect(cubit.state.playback, PlaybackSnapshot.idle);
    expect(emittedStates, isEmpty);
  });

  test('boundary failures do not mutate the confirmed state', () async {
    final item = testPlayerItem();
    final confirmed = buildPlaybackSnapshot(
      currentItem: item,
      queue: [item],
      currentIndex: 0,
      processingState: PlaybackProcessingState.ready,
      playing: true,
    );
    final emptyFailure = const PlayerCommandFailure(
      code: 'emptyQueue',
      message: 'Queue cannot be empty.',
      command: 'loadQueue',
    );
    final invalidIndexFailure = const PlayerCommandFailure(
      code: 'initialIndexOutOfRange',
      message: 'Initial index is outside the queue.',
      command: 'loadQueue',
    );
    final previousGateway = gateway;
    gateway = FakePlaybackGateway(
      initialSnapshot: confirmed,
      commandBehaviors: <String, FakeCommandBehavior>{
        'loadQueue': (command) {
          final items = command.arguments['items']! as List<Object?>;
          final initialIndex = command.arguments['initialIndex']! as int;
          if (items.isEmpty) {
            throw emptyFailure;
          }
          if (initialIndex < 0 || initialIndex >= items.length) {
            throw invalidIndexFailure;
          }
        },
      },
    );
    await cubit.close();
    await previousGateway.dispose();
    cubit = PlayerCubit(gateway);
    gateway.emit(confirmed);
    await _flushStreamEvents();
    final stateBefore = cubit.state;
    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await expectLater(
      cubit.openQueue(const [], initialIndex: 0),
      throwsA(same(emptyFailure)),
    );
    await expectLater(
      cubit.openQueue([item], initialIndex: 1),
      throwsA(same(invalidIndexFailure)),
    );
    await expectLater(
      cubit.openQueue([item], initialIndex: -1),
      throwsA(same(invalidIndexFailure)),
    );

    expect(cubit.state, stateBefore);
    expect(cubit.state.currentItem, same(item));
    expect(cubit.state.playing, isTrue);
    expect(emittedStates, isEmpty);
  });

  test(
    'gateway throw does not create a playing or current-item state',
    () async {
      final failure = StateError('gateway failed');
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(
        commandBehaviors: <String, FakeCommandBehavior>{
          'loadQueue': (_) => throw failure,
        },
      );
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);
      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await expectLater(cubit.open(testPlayerItem()), throwsA(same(failure)));

      expect(cubit.state.playback, PlaybackSnapshot.idle);
      expect(cubit.state.currentItem, isNull);
      expect(cubit.state.playing, isFalse);
      expect(emittedStates, isEmpty);
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
