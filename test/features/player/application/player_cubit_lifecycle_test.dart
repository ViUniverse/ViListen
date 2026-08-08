// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
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

  test(
    'snapshot after close does not emit and subscription cancels once',
    () async {
      final initial = buildPlaybackSnapshot(currentItem: testPlayerItem());
      gateway.emit(initial);
      await _flushStreamEvents();

      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await Future.wait<void>([cubit.close(), cubit.close()]);

      gateway.emit(initial.copyWith(position: const Duration(seconds: 5)));
      await _flushStreamEvents();

      expect(gateway.snapshotSubscriptionCancelCount, 1);
      expect(cubit.isClosed, isTrue);
      expect(cubit.state.playback, same(initial));
      expect(emittedStates, isEmpty);
    },
  );

  test('close does not issue stop or dispose commands', () async {
    await cubit.close();

    expect(gateway.commands, isEmpty);
  });

  test(
    'surfaces typed command failure without guessed playback state',
    () async {
      const failure = PlayerCommandFailure(
        code: 'noCurrentItem',
        message: 'No current item.',
        command: 'play',
      );
      final failureGateway = FakePlaybackGateway(
        commandBehaviors: <String, FakeCommandBehavior>{
          'play': (_) => throw failure,
        },
      );
      final failureCubit = PlayerCubit(failureGateway);
      addTearDown(() async {
        await failureCubit.close();
        await failureGateway.dispose();
      });

      final stateBefore = failureCubit.state;
      final emittedStates = <PlayerState>[];
      final subscription = failureCubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await expectLater(failureCubit.play(), throwsA(same(failure)));
      await _flushStreamEvents();

      expect(failureCubit.state, same(stateBefore));
      expect(failureCubit.state.playback, same(PlaybackSnapshot.idle));
      expect(emittedStates, isEmpty);
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
