// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_call_recorder.dart';
import '../support/player_test_data.dart';

void main() {
  late _SpeedTestEngine engine;
  late AppAudioHandler handler;

  setUp(() {
    engine = _SpeedTestEngine(FakePlaybackEngine());
    handler = AppAudioHandler(engine, FakePlayerClock());
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('rejects invalid speed before readiness and engine access', () async {
    final invalidSpeeds = <double>[
      0.499,
      2.001,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ];

    for (final speed in invalidSpeeds) {
      await expectLater(
        handler.handleSetSpeed(speed, CommandSource.ui),
        _invalidSpeedFailure,
      );
    }

    expect(engine.calls, isEmpty);
    expect(handler.playbackState.value.speed, 1.0);
  });

  test(
    'accepts every UI preset and confirms each through speedStream',
    () async {
      await _loadReady(handler, engine, 'preset-track');

      const presets = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
      for (final speed in presets) {
        await handler.handleSetSpeed(speed, CommandSource.ui);
        expect(engine.speedCalls.last, speed);

        engine.emitSpeed(speed);
        await pumpEventQueue();

        expect(handler.playbackState.value.speed, speed);
      }

      expect(engine.speedCalls, presets);
    },
  );

  test('accepts finite API values that are not UI presets', () async {
    await _loadReady(handler, engine, 'api-speed-track');

    await handler.handleSetSpeed(1.1, CommandSource.ui);
    expect(engine.speedCalls, [1.1]);

    engine.emitSpeed(1.1);
    await pumpEventQueue();

    expect(handler.playbackState.value.speed, 1.1);
  });

  test('does not publish snapshot or OS speed before confirmation', () async {
    final snapshots = <PlaybackSnapshot>[];
    final playbackStates = <audio_service.PlaybackState>[];
    final snapshotSubscription = handler.snapshots.listen(snapshots.add);
    final playbackStateSubscription = handler.playbackState.listen(
      playbackStates.add,
    );
    addTearDown(snapshotSubscription.cancel);
    addTearDown(playbackStateSubscription.cancel);

    await _loadReady(handler, engine, 'confirmation-track');
    snapshots.clear();
    playbackStates.clear();

    await handler.handleSetSpeed(1.25, CommandSource.ui);
    await pumpEventQueue();

    expect(snapshots, isEmpty);
    expect(playbackStates, isEmpty);
    expect(handler.playbackState.value.speed, 1.0);

    engine.emitSpeed(1.25);
    await pumpEventQueue();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.speed, 1.25);
    expect(playbackStates, hasLength(1));
    expect(playbackStates.single.speed, 1.25);
  });

  test('coalesces identical speed requests until confirmation', () async {
    await _loadReady(handler, engine, 'coalesce-track');
    final platformCall = Completer<void>();
    engine.speedAction = (_) => platformCall.future;

    final first = handler.handleSetSpeed(1.25, CommandSource.ui);
    final second = handler.handleSetSpeed(1.25, CommandSource.ui);

    expect(identical(first, second), isTrue);
    expect(engine.speedCalls, [1.25]);

    platformCall.complete();
    await first;
    engine.emitSpeed(1.25);
    await pumpEventQueue();
    expect(handler.playbackState.value.speed, 1.25);
  });

  test('keeps the latest speed in a ready A-B-A burst', () async {
    await _loadReady(handler, engine, 'ready-a-b-a-track');

    final firstPlatformCall = Completer<void>();
    var speedCallNumber = 0;
    engine.speedAction = (_) {
      speedCallNumber += 1;
      return speedCallNumber == 1
          ? firstPlatformCall.future
          : Future<void>.value();
    };

    final firstA = handler.handleSetSpeed(1.25, CommandSource.ui);
    final b = handler.handleSetSpeed(1.5, CommandSource.ui);
    final lastA = handler.handleSetSpeed(1.25, CommandSource.ui);

    expect(engine.speedCalls, [1.25]);

    firstPlatformCall.complete();
    await firstA;
    await b;
    await pumpEventQueue();

    expect(engine.speedCalls, [1.25, 1.25]);

    engine.emitSpeed(1.25);
    await lastA;
    await pumpEventQueue();

    expect(engine.speedCalls, isNot(contains(1.5)));
    expect(handler.playbackState.value.speed, 1.25);
  });

  test('queues a newer speed and ignores stale confirmation', () async {
    await _loadReady(handler, engine, 'latest-speed-track');
    final firstPlatformCall = Completer<void>();
    final secondPlatformCall = Completer<void>();
    engine.speedAction = (speed) =>
        speed == 1.25 ? firstPlatformCall.future : secondPlatformCall.future;

    final first = handler.handleSetSpeed(1.25, CommandSource.ui);
    final second = handler.handleSetSpeed(1.5, CommandSource.ui);
    expect(engine.speedCalls, [1.25]);

    firstPlatformCall.complete();
    await first;
    await pumpEventQueue();
    expect(engine.speedCalls, [1.25, 1.5]);

    engine.emitSpeed(1.25);
    await pumpEventQueue();
    expect(handler.playbackState.value.speed, 1.0);

    engine.emitSpeed(1.5);
    secondPlatformCall.complete();
    await second;
    await pumpEventQueue();
    expect(handler.playbackState.value.speed, 1.5);
  });

  test('applies desired speed before committing a pending load', () async {
    final load = handler.handleLoadQueue(
      [testPlayerItem(id: 'pending-speed-track')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    final speedPlatformCall = Completer<void>();
    engine.speedAction = (_) => speedPlatformCall.future;
    final speed = handler.handleSetSpeed(1.25, CommandSource.ui);
    expect(engine.speedCalls, [1.25]);

    speedPlatformCall.complete();
    await speed;
    engine.emitSpeed(1.25);
    await pumpEventQueue();

    engine.delegate.loadRequests.single.complete();
    await load;
    await pumpEventQueue();

    expect(handler.playbackState.value.speed, 1.25);
  });

  test('keeps the latest speed in a pending-load A-B-A burst', () async {
    final load = handler.handleLoadQueue(
      [testPlayerItem(id: 'pending-a-b-a-track')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    final firstPlatformCall = Completer<void>();
    var speedCallNumber = 0;
    engine.speedAction = (_) {
      speedCallNumber += 1;
      return speedCallNumber == 1
          ? firstPlatformCall.future
          : Future<void>.value();
    };

    final firstA = handler.handleSetSpeed(1.25, CommandSource.ui);
    final b = handler.handleSetSpeed(1.5, CommandSource.ui);
    final lastA = handler.handleSetSpeed(1.25, CommandSource.ui);

    expect(engine.speedCalls, [1.25]);

    firstPlatformCall.complete();
    await firstA;
    await b;
    await pumpEventQueue();
    expect(engine.speedCalls, [1.25, 1.25]);

    engine.emitSpeed(1.25);
    await lastA;
    await pumpEventQueue();

    engine.delegate.loadRequests.single.complete();
    await load;
    await pumpEventQueue();

    expect(engine.speedCalls, [1.25, 1.25]);
    expect(handler.playbackState.value.speed, 1.25);
  });

  test('a newer load reapplies the desired speed for its generation', () async {
    final itemB = testPlayerItem(id: 'speed-track-b');
    final itemC = testPlayerItem(id: 'speed-track-c');
    final loadB = handler.handleLoadQueue([itemB], 0, false, CommandSource.ui);
    await pumpEventQueue();

    var speedCallNumber = 0;
    final secondSpeedPlatformCall = Completer<void>();
    engine.speedAction = (_) {
      speedCallNumber += 1;
      return speedCallNumber == 1
          ? Future<void>.value()
          : secondSpeedPlatformCall.future;
    };

    await handler.handleSetSpeed(1.25, CommandSource.ui);
    engine.emitSpeed(1.25);
    await pumpEventQueue();

    final loadC = handler.handleLoadQueue([itemC], 0, false, CommandSource.ui);
    await pumpEventQueue();
    engine.delegate.loadRequests.last.complete();
    await pumpEventQueue();

    expect(engine.speedCalls, [1.25, 1.25]);
    expect(handler.mediaItem.value, isNull);

    engine.emitSpeed(1.25);
    secondSpeedPlatformCall.complete();
    await loadB;
    await loadC;
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, itemC.id);
    expect(handler.playbackState.value.speed, 1.25);
  });

  test('a newer load replaces a load waiting on speed preparation', () async {
    await _loadReady(handler, engine, 'speed-track-a');

    final itemC = testPlayerItem(id: 'speed-track-c');
    final itemD = testPlayerItem(id: 'speed-track-d');
    final loadC = handler.handleLoadQueue([itemC], 0, false, CommandSource.ui);
    await pumpEventQueue();

    var speedCallNumber = 0;
    final cSpeedPlatformCall = Completer<void>();
    final dSpeedPlatformCall = Completer<void>();
    engine.speedAction = (_) {
      speedCallNumber += 1;
      return speedCallNumber == 1
          ? cSpeedPlatformCall.future
          : dSpeedPlatformCall.future;
    };

    final cSpeed = handler.handleSetSpeed(1.25, CommandSource.ui);
    expect(engine.speedCalls, [1.25]);

    engine.delegate.loadRequests[1].complete();
    await pumpEventQueue();

    final loadD = handler.handleLoadQueue([itemD], 0, false, CommandSource.ui);
    await pumpEventQueue();

    expect(
      engine.calls.where((call) => call.name == 'interruptLoad'),
      hasLength(1),
    );
    expect(engine.delegate.loadRequests, hasLength(3));

    engine.delegate.loadRequests[2].complete();
    await pumpEventQueue();
    expect(engine.speedCalls, [1.25, 1.25]);

    dSpeedPlatformCall.complete();
    await pumpEventQueue();
    engine.emitSpeed(1.25);

    await Future.wait<void>([loadC, loadD, cSpeed]);
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, itemD.id);
    expect(handler.playbackState.value.speed, 1.25);

    // The stale platform future may still complete after C was interrupted;
    // its callback must not affect D's generation.
    cSpeedPlatformCall.complete();
  });

  test('engine failure leaves no stale flight for the next command', () async {
    await _loadReady(handler, engine, 'failure-track');
    engine.speedAction = (_) => Future<void>.error(StateError('speed failed'));

    await expectLater(
      handler.handleSetSpeed(1.25, CommandSource.ui),
      throwsA(isA<StateError>()),
    );
    expect(handler.playbackState.value.speed, 1.0);

    engine.speedAction = (_) => Future<void>.value();
    await handler.handleSetSpeed(1.5, CommandSource.ui);
    engine.emitSpeed(1.5);
    await pumpEventQueue();

    expect(handler.playbackState.value.speed, 1.5);
  });
}

Matcher get _invalidSpeedFailure => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', 'invalidSpeed')
      .having((failure) => failure.command, 'command', 'setSpeed')
      .having(
        (failure) => failure.message,
        'message',
        'Speed must be between 0.5 and 2.0.',
      ),
);

Future<void> _loadReady(
  AppAudioHandler handler,
  _SpeedTestEngine engine,
  String id,
) async {
  final load = handler.handleLoadQueue(
    [testPlayerItem(id: id)],
    0,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.delegate.loadRequests.last.complete();
  await load;
  await pumpEventQueue();
}

final class _SpeedTestEngine implements PlaybackEngine {
  _SpeedTestEngine(this.delegate);

  final FakePlaybackEngine delegate;
  Future<void> Function(double speed)? speedAction;

  List<RecordedPlayerCall> get calls => delegate.calls;

  List<double> get speedCalls => calls
      .where((call) => call.name == 'setSpeed')
      .map((call) => call.arguments['speed']! as double)
      .toList(growable: false);

  void emitSpeed(double speed) => delegate.emitSpeed(speed);

  @override
  Stream<PlaybackEngineEvent> get sourceEvents => delegate.sourceEvents;

  @override
  Stream<just_audio.PlayerState> get playerStateStream =>
      delegate.playerStateStream;

  @override
  Stream<Duration> get positionStream => delegate.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      delegate.bufferedPositionStream;

  @override
  Stream<Duration?> get durationStream => delegate.durationStream;

  @override
  Stream<int?> get currentIndexStream => delegate.currentIndexStream;

  @override
  Stream<List<int>> get effectiveSequenceStream =>
      delegate.effectiveSequenceStream;

  @override
  Stream<double> get speedStream => delegate.speedStream;

  @override
  Stream<just_audio.LoopMode> get loopModeStream => delegate.loopModeStream;

  @override
  Stream<bool> get shuffleModeEnabledStream =>
      delegate.shuffleModeEnabledStream;

  @override
  Stream<just_audio.PlayerException> get errorStream => delegate.errorStream;

  @override
  Future<void> load(
    List<just_audio.AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  }) => delegate.load(
    sources,
    initialIndex: initialIndex,
    sourceGeneration: sourceGeneration,
  );

  @override
  Future<void> interruptLoad() => delegate.interruptLoad();

  @override
  Future<void> play() => delegate.play();

  @override
  Future<void> pause() => delegate.pause();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> seek(Duration position, {int? index}) =>
      delegate.seek(position, index: index);

  @override
  Future<void> setSpeed(double speed) {
    delegate.setSpeed(speed);
    return speedAction?.call(speed) ?? Future<void>.value();
  }

  @override
  Future<void> setLoopMode(just_audio.LoopMode mode) =>
      delegate.setLoopMode(mode);

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      delegate.setShuffleEnabled(enabled);

  @override
  Future<void> dispose() => delegate.dispose();
}
