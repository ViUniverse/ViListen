// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'fake_playback_gateway.dart';
import 'playback_snapshot_builder.dart';
import 'player_test_data.dart';

void main() {
  group('FakePlaybackGateway snapshots', () {
    test(
      'replays the initial snapshot asynchronously to each subscriber',
      () async {
        final gateway = FakePlaybackGateway();
        addTearDown(gateway.dispose);

        expect(gateway.snapshots.isBroadcast, isTrue);

        final firstValues = <Object>[];
        final secondValues = <Object>[];
        final firstSubscription = gateway.snapshots.listen(firstValues.add);
        final secondSubscription = gateway.snapshots.listen(secondValues.add);
        addTearDown(firstSubscription.cancel);
        addTearDown(secondSubscription.cancel);

        expect(firstValues, isEmpty);
        expect(secondValues, isEmpty);

        await Future<void>.microtask(() {});

        expect(firstValues, [PlaybackSnapshot.idle]);
        expect(secondValues, [PlaybackSnapshot.idle]);
      },
    );

    test(
      'emits live snapshots and replays only the latest value once',
      () async {
        final gateway = FakePlaybackGateway();
        addTearDown(gateway.dispose);

        final first = buildPlaybackSnapshot(
          position: const Duration(seconds: 1),
        );
        final second = buildPlaybackSnapshot(
          position: const Duration(seconds: 2),
        );
        final received = <Object>[];

        gateway.emit(first);
        final subscription = gateway.snapshots.listen(received.add);
        addTearDown(subscription.cancel);

        expect(received, isEmpty);
        await Future<void>.microtask(() {});
        expect(received, [first]);

        gateway.emit(second);
        await Future<void>.delayed(Duration.zero);
        expect(received, [first, second]);

        final lateReceived = <Object>[];
        final lateSubscription = gateway.snapshots.listen(lateReceived.add);
        addTearDown(lateSubscription.cancel);

        await Future<void>.microtask(() {});
        expect(lateReceived, [second]);
      },
    );
  });

  group('FakePlaybackGateway commands', () {
    test('records command names, arguments, order, and call count', () async {
      final gateway = FakePlaybackGateway();
      addTearDown(gateway.dispose);

      final first = testPlayerItem(id: 'track-1');
      final second = testPlayerItem(id: 'track-2');
      final items = <PlayerItem>[first, second];

      await gateway.loadQueue(items, initialIndex: 1, autoplay: false);
      await gateway.play();
      await gateway.play();
      await gateway.pause();
      await gateway.stop();
      await gateway.seek(const Duration(seconds: 12));
      await gateway.skipBy(const Duration(seconds: -10));
      await gateway.next();
      await gateway.previous();
      await gateway.setSpeed(1.5);
      await gateway.setRepeatMode(PlayerRepeatMode.all);
      await gateway.setShuffleEnabled(true);
      await gateway.retry();

      expect(gateway.commands.map((command) => command.name), [
        'loadQueue',
        'play',
        'play',
        'pause',
        'stop',
        'seek',
        'skipBy',
        'next',
        'previous',
        'setSpeed',
        'setRepeatMode',
        'setShuffleEnabled',
        'retry',
      ]);
      expect(gateway.commands.map((command) => command.order), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
      ]);
      expect(gateway.callCountFor('play'), 2);
      expect(gateway.commands[1].callCount, 1);
      expect(gateway.commands[2].callCount, 2);
      expect(gateway.commands[0].arguments, {
        'items': [first, second],
        'initialIndex': 1,
        'autoplay': false,
      });
      expect(gateway.commands[5].arguments, {
        'position': const Duration(seconds: 12),
      });
      expect(gateway.commands[6].arguments, {
        'offset': const Duration(seconds: -10),
      });
      expect(gateway.commands[9].arguments, {'speed': 1.5});
      expect(gateway.commands[10].arguments, {'mode': PlayerRepeatMode.all});
      expect(gateway.commands[11].arguments, {'enabled': true});
      expect(gateway.commands[1].arguments, isEmpty);
      expect(gateway.commands[0].arguments['items'], isNot(same(items)));
    });

    test(
      'supports delayed command completion without wall-clock timing',
      () async {
        final completion = Completer<void>();
        final gateway = FakePlaybackGateway(
          commandBehaviors: <String, FakeCommandBehavior>{
            'play': (_) => completion.future,
          },
        );
        addTearDown(gateway.dispose);

        var completed = false;
        final commandFuture = gateway.play().then((_) => completed = true);

        await Future<void>.microtask(() {});
        expect(completed, isFalse);
        expect(gateway.commands.single.name, 'play');

        completion.complete();
        await commandFuture;

        expect(completed, isTrue);
      },
    );

    test('propagates command errors without emitting a snapshot', () async {
      final error = StateError('play failed');
      final gateway = FakePlaybackGateway(
        commandBehaviors: <String, FakeCommandBehavior>{
          'play': (_) => Future<void>.error(error),
        },
      );
      addTearDown(gateway.dispose);

      final received = <Object>[];
      final subscription = gateway.snapshots.listen(received.add);
      addTearDown(subscription.cancel);
      await Future<void>.microtask(() {});

      await expectLater(gateway.play(), throwsA(same(error)));
      await Future<void>.delayed(Duration.zero);

      expect(received, [PlaybackSnapshot.idle]);
      expect(gateway.commands.single.name, 'play');
    });
  });

  test(
    'dispose closes active and future subscriptions without leaking',
    () async {
      final gateway = FakePlaybackGateway();
      final subscription = gateway.snapshots.listen((_) {});
      final done = subscription.asFuture<void>();

      await gateway.dispose();
      await done;
      await gateway.dispose();

      await expectLater(gateway.snapshots, emitsDone);
    },
  );
}
