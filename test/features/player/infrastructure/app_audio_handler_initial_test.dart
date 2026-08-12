// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/playback_gateway.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';

void main() {
  late FakePlaybackEngine engine;
  late FakePlayerClock clock;
  late AppAudioHandler handler;
  late List<({String command, CommandSource source})> observedCommands;

  setUp(() {
    engine = FakePlaybackEngine();
    clock = FakePlayerClock();
    observedCommands = <({String command, CommandSource source})>[];
    handler = AppAudioHandler(
      engine,
      clock,
      (command, source) =>
          observedCommands.add((command: command, source: source)),
    );
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('starts with canonical domain and audio-service idle state', () {
    expect(handler.snapshots.isBroadcast, isTrue);
    expect(handler.mediaItem.value, isNull);
    expect(handler.queue.value, isEmpty);

    final state = handler.playbackState.value;
    expect(state.processingState, audio_service.AudioProcessingState.idle);
    expect(state.playing, isFalse);
    expect(state.controls, isEmpty);
    expect(state.systemActions, isEmpty);
    expect(state.updatePosition, Duration.zero);
    expect(state.bufferedPosition, Duration.zero);
    expect(state.speed, 1.0);
    expect(state.repeatMode, audio_service.AudioServiceRepeatMode.none);
    expect(state.shuffleMode, audio_service.AudioServiceShuffleMode.none);
    expect(state.queueIndex, isNull);
  });

  test(
    'replays the latest idle snapshot asynchronously once per subscriber',
    () async {
      final firstSnapshots = <PlaybackSnapshot>[];
      final secondSnapshots = <PlaybackSnapshot>[];
      final first = handler.snapshots.listen(firstSnapshots.add);
      final second = handler.snapshots.listen(secondSnapshots.add);

      expect(firstSnapshots, isEmpty);
      expect(secondSnapshots, isEmpty);

      await pumpEventQueue();

      expect(firstSnapshots, [PlaybackSnapshot.idle]);
      expect(secondSnapshots, [PlaybackSnapshot.idle]);

      await first.cancel();
      expect(second.isPaused, isFalse);
      await second.cancel();
    },
  );

  test('does not add an extra system publication while idle', () async {
    final playbackStates = <audio_service.PlaybackState>[];
    final mediaItems = <audio_service.MediaItem?>[];
    final queues = <List<audio_service.MediaItem>>[];
    final playbackSubscription = handler.playbackState.listen(
      playbackStates.add,
    );
    final mediaItemSubscription = handler.mediaItem.listen(mediaItems.add);
    final queueSubscription = handler.queue.listen(queues.add);

    await pumpEventQueue();

    expect(playbackStates, hasLength(1));
    expect(mediaItems, [null]);
    expect(queues, [[]]);

    await playbackSubscription.cancel();
    await mediaItemSubscription.cancel();
    await queueSubscription.cancel();
  });

  test('production factory creates exactly one engine and one clock', () async {
    var engineCount = 0;
    var clockCount = 0;
    final fakeEngine = FakePlaybackEngine();
    final fakeClock = FakePlayerClock();

    final productionHandler = AppAudioHandler.production(
      engineFactory: () {
        engineCount += 1;
        return fakeEngine;
      },
      clockFactory: () {
        clockCount += 1;
        return fakeClock;
      },
    );

    expect(engineCount, 1);
    expect(clockCount, 1);

    await productionHandler.dispose();
    expect(fakeEngine.disposeCount, 1);
    expect(fakeClock.disposeCount, 1);
  });

  test(
    'composes through PlaybackGateway without exposing the handler publicly',
    () async {
      final PlaybackGateway gateway = UiPlaybackGatewayAdapter(handler);
      final snapshots = <PlaybackSnapshot>[];
      final subscription = gateway.snapshots.listen(snapshots.add);

      await pumpEventQueue();

      expect(snapshots, [PlaybackSnapshot.idle]);

      await subscription.cancel();
    },
  );

  test('preserves UI and system provenance on the real handler', () async {
    final PlaybackGateway gateway = UiPlaybackGatewayAdapter(handler);

    await expectLater(gateway.play(), _noCurrentItemFailure('play'));
    await expectLater(handler.play(), _noCurrentItemFailure('play'));

    expect(observedCommands, [
      (command: 'play', source: CommandSource.ui),
      (command: 'play', source: CommandSource.systemRemote),
    ]);
  });

  test('observer failure does not replace the typed command failure', () async {
    final failingObserverHandler = AppAudioHandler(
      FakePlaybackEngine(),
      FakePlayerClock(),
      (_, _) => throw StateError('observer failure'),
    );
    addTearDown(failingObserverHandler.dispose);

    await expectLater(
      failingObserverHandler.play(),
      _noCurrentItemFailure('play'),
    );
  });

  test('dispose is idempotent and closes owned resources once', () async {
    final snapshotsDone = handler.snapshots.listen((_) {}).asFuture<void>();
    final firstDispose = handler.dispose();
    final secondDispose = handler.dispose();

    expect(identical(firstDispose, secondDispose), isTrue);

    await firstDispose;
    await snapshotsDone;
    expect(engine.disposeCount, 1);
    expect(clock.disposeCount, 1);
  });
}

Matcher _noCurrentItemFailure(String command) => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', 'noCurrentItem')
      .having((failure) => failure.command, 'command', command)
      .having(
        (failure) => failure.message,
        'message',
        'Playback command requires a current item.',
      ),
);
