// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_command_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
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

  test('setSpeed forwards any valid speed without optimistic state', () async {
    final emittedStates = <PlayerState>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.setSpeed(1.1);

    expect(gateway.callCountFor('setSpeed'), 1);
    expect(gateway.commands.single.arguments, {'speed': 1.1});
    expect(cubit.state.playback.speed, 1.0);
    expect(emittedStates, isEmpty);
  });

  test(
    'setSpeed propagates Gateway validation without optimistic state',
    () async {
      final invalidSpeeds = <double>[
        0.499,
        2.001,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];
      const expectedFailure = PlayerCommandFailure(
        code: 'invalidSpeed',
        message: 'Speed must be between 0.5 and 2.0.',
        command: 'setSpeed',
      );
      final previousGateway = gateway;
      gateway = FakePlaybackGateway(
        commandBehaviors: <String, FakeCommandBehavior>{
          'setSpeed': (_) => throw expectedFailure,
        },
      );
      await cubit.close();
      await previousGateway.dispose();
      cubit = PlayerCubit(gateway);
      await _flushStreamEvents();

      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      for (final speed in invalidSpeeds) {
        await expectLater(cubit.setSpeed(speed), throwsA(expectedFailure));
      }

      expect(gateway.callCountFor('setSpeed'), invalidSpeeds.length);
      expect(
        gateway.commands.map((command) => command.arguments['speed']),
        invalidSpeeds,
      );
      expect(cubit.state.playback.speed, 1.0);
      expect(emittedStates, isEmpty);
    },
  );

  test(
    'cycleRepeatMode follows confirmed off, one, all, and off states',
    () async {
      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      for (final expectedMode in const [
        PlayerRepeatMode.one,
        PlayerRepeatMode.all,
        PlayerRepeatMode.off,
      ]) {
        await cubit.cycleRepeatMode();

        expect(gateway.commands.last.arguments, {'mode': expectedMode});
        expect(cubit.state.playback.repeatMode, isNot(expectedMode));
        expect(
          emittedStates,
          hasLength(gateway.callCountFor('setRepeatMode') - 1),
        );

        final confirmed = buildPlaybackSnapshot(repeatMode: expectedMode);
        gateway.emit(confirmed);
        await _flushStreamEvents();

        expect(cubit.state.playback, same(confirmed));
      }

      expect(gateway.callCountFor('setRepeatMode'), 3);
      expect(emittedStates.map((state) => state.playback.repeatMode), const [
        PlayerRepeatMode.one,
        PlayerRepeatMode.all,
        PlayerRepeatMode.off,
      ]);
    },
  );

  test(
    'cycleRepeatMode uses confirmed mode until a snapshot arrives',
    () async {
      await cubit.cycleRepeatMode();
      await cubit.cycleRepeatMode();

      expect(
        gateway.commands.map((command) => command.arguments['mode']),
        const [PlayerRepeatMode.one, PlayerRepeatMode.one],
      );
      expect(cubit.state.playback.repeatMode, PlayerRepeatMode.off);
    },
  );

  test(
    'toggleShuffle sends the opposite confirmed value without early emit',
    () async {
      final confirmedOff = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        shuffleEnabled: false,
      );
      gateway.emit(confirmedOff);
      await _flushStreamEvents();

      final emittedStates = <PlayerState>[];
      final subscription = cubit.stream.listen(emittedStates.add);
      addTearDown(subscription.cancel);

      await cubit.toggleShuffle();
      await cubit.toggleShuffle();

      expect(
        gateway.commands.map((command) => command.arguments['enabled']),
        const [true, true],
      );
      expect(cubit.state.playback, same(confirmedOff));
      expect(emittedStates, isEmpty);

      final confirmedOn = confirmedOff.copyWith(shuffleEnabled: true);
      gateway.emit(confirmedOn);
      await _flushStreamEvents();

      await cubit.toggleShuffle();

      expect(gateway.commands.last.arguments, {'enabled': false});
      expect(cubit.state.playback, same(confirmedOn));
      expect(emittedStates, [PlayerState.fromSnapshot(confirmedOn)]);
    },
  );
}

Future<void> _flushStreamEvents() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
