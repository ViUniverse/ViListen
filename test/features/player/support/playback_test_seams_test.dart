import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/command_source.dart';
import 'fake_playback_engine.dart';
import 'fake_player_clock.dart';
import 'player_call_recorder.dart';

void main() {
  group('FakePlaybackEngine streams', () {
    test('emits every engine stream independently', () async {
      final engine = FakePlaybackEngine();
      addTearDown(engine.dispose);

      final playerStates = <PlayerState>[];
      final positions = <Duration>[];
      final bufferedPositions = <Duration>[];
      final durations = <Duration?>[];
      final indexes = <int?>[];
      final sequences = <List<int>>[];
      final speeds = <double>[];
      final loopModes = <LoopMode>[];
      final shuffleModes = <bool>[];
      final errors = <PlayerException>[];

      final subscriptions = <StreamSubscription<Object?>>[
        engine.playerStateStream.listen(playerStates.add),
        engine.positionStream.listen(positions.add),
        engine.bufferedPositionStream.listen(bufferedPositions.add),
        engine.durationStream.listen(durations.add),
        engine.currentIndexStream.listen(indexes.add),
        engine.effectiveSequenceStream.listen(sequences.add),
        engine.speedStream.listen(speeds.add),
        engine.loopModeStream.listen(loopModes.add),
        engine.shuffleModeEnabledStream.listen(shuffleModes.add),
        engine.errorStream.listen(errors.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });

      final playerState = PlayerState(true, ProcessingState.buffering);
      final error = PlayerException(7, 'test error', 0);
      engine.emitPlayerState(playerState);
      expect(playerStates, [playerState]);
      expect(positions, isEmpty);
      expect(bufferedPositions, isEmpty);
      expect(durations, isEmpty);
      expect(indexes, isEmpty);
      expect(sequences, isEmpty);
      expect(speeds, isEmpty);
      expect(loopModes, isEmpty);
      expect(shuffleModes, isEmpty);
      expect(errors, isEmpty);

      engine.emitPosition(const Duration(seconds: 1));
      engine.emitBufferedPosition(const Duration(seconds: 2));
      engine.emitDuration(const Duration(seconds: 3));
      engine.emitCurrentIndex(1);
      engine.emitEffectiveSequence([1, 0]);
      engine.emitSpeed(1.25);
      engine.emitLoopMode(LoopMode.all);
      engine.emitShuffleModeEnabled(true);
      engine.emitError(error);

      expect(positions, [const Duration(seconds: 1)]);
      expect(bufferedPositions, [const Duration(seconds: 2)]);
      expect(durations, [const Duration(seconds: 3)]);
      expect(indexes, [1]);
      expect(sequences, [
        [1, 0],
      ]);
      expect(speeds, [1.25]);
      expect(loopModes, [LoopMode.all]);
      expect(shuffleModes, [true]);
      expect(errors, [error]);
    });
  });

  group('FakePlaybackEngine loads', () {
    test('keeps a load pending until the test completes it', () async {
      final engine = FakePlaybackEngine();
      addTearDown(engine.dispose);
      final source = AudioSource.uri(Uri.parse('https://example.test/a.mp3'));

      final loadFuture = engine.load([source], initialIndex: 0);
      final request = engine.loadRequests.single;
      var completed = false;
      loadFuture.then((_) => completed = true);

      await Future<void>.microtask(() {});
      expect(completed, isFalse);
      expect(request.isCompleted, isFalse);

      request.complete();
      await loadFuture;

      expect(completed, isTrue);
      expect(engine.callCountFor('load'), 1);
      expect(engine.calls.single.arguments, {
        'sources': [source],
        'initialIndex': 0,
      });
    });

    test('propagates a controllable load error', () async {
      final engine = FakePlaybackEngine();
      addTearDown(engine.dispose);
      final error = StateError('load failed');
      final stackTrace = StackTrace.current;
      final loadFuture = engine.load([
        AudioSource.uri(Uri.parse('https://example.test/a.mp3')),
      ], initialIndex: 0);
      final observed = expectLater(loadFuture, throwsA(same(error)));

      engine.loadRequests.single.completeError(error, stackTrace);
      await observed;
    });

    test(
      'allows stale success/error completion in deterministic order',
      () async {
        final engine = FakePlaybackEngine();
        addTearDown(engine.dispose);

        final firstFuture = engine.load([
          AudioSource.uri(Uri.parse('https://example.test/a.mp3')),
        ], initialIndex: 0);
        final secondFuture = engine.load([
          AudioSource.uri(Uri.parse('https://example.test/b.mp3')),
        ], initialIndex: 0);
        final secondRequest = engine.loadRequests[1];
        final firstRequest = engine.loadRequests[0];
        final firstError = StateError('stale load failed');
        final firstObserved = expectLater(
          firstFuture,
          throwsA(same(firstError)),
        );

        secondRequest.complete();
        await secondFuture;
        expect(firstRequest.isCompleted, isFalse);

        firstRequest.completeError(firstError);
        await firstObserved;
        expect(engine.loadRequests, [firstRequest, secondRequest]);
      },
    );
  });

  test('records names, arguments, source, order, and per-name counts', () {
    final recorder = PlayerCallRecorder();

    recorder.record('play', source: CommandSource.ui);
    recorder.record('pause', source: CommandSource.systemRemote);
    recorder.record(
      'seek',
      arguments: <String, Object?>{'position': const Duration(seconds: 4)},
      source: CommandSource.ui,
    );
    recorder.record('play', source: CommandSource.interruption);

    expect(recorder.calls.map((call) => call.name), [
      'play',
      'pause',
      'seek',
      'play',
    ]);
    expect(recorder.calls.map((call) => call.order), [1, 2, 3, 4]);
    expect(recorder.calls[0].source, CommandSource.ui);
    expect(recorder.calls[1].source, CommandSource.systemRemote);
    expect(recorder.calls[2].arguments, {
      'position': const Duration(seconds: 4),
    });
    expect(recorder.calls[3].callCount, 2);
    expect(recorder.callCountFor('play'), 2);
  });

  test('fake clock advances synchronously without sleeping', () async {
    final clock = FakePlayerClock();
    final ticks = <Duration>[];
    final subscription = clock.ticks.listen(ticks.add);
    addTearDown(subscription.cancel);

    clock.advance(const Duration(milliseconds: 200));

    expect(clock.elapsed, const Duration(milliseconds: 200));
    expect(ticks, [const Duration(milliseconds: 200)]);

    await clock.dispose();
    await clock.dispose();
    expect(clock.disposeCount, 1);
  });

  test('engine dispose is idempotent and closes its streams', () async {
    final engine = FakePlaybackEngine();
    final subscription = engine.positionStream.listen((_) {});
    final done = subscription.asFuture<void>();

    await engine.dispose();
    await done;
    await engine.dispose();

    expect(engine.disposeCount, 1);
    await expectLater(engine.positionStream, emitsDone);
  });
}
