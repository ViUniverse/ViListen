// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/interruption_observer.dart';
import 'package:vi_listen/features/player/infrastructure/player_logger.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  test('typed logger emits the canonical event names and exact fields', () {
    final events = <_LogEvent>[];
    final logger = PlayerLogger((event, fields) {
      events.add(_LogEvent(event, fields));
    });

    logger.loadStarted(
      itemId: 'track-1',
      generation: 1,
      index: 0,
      source: CommandSource.ui,
    );
    logger.loadReady(
      itemId: 'track-1',
      generation: 1,
      index: 0,
      durationMs: 2000,
      latencyMs: 125,
      source: CommandSource.systemRemote,
    );
    logger.play(itemId: 'track-1', positionMs: 10, source: CommandSource.ui);
    logger.pause(
      itemId: 'track-1',
      positionMs: 20,
      source: CommandSource.systemRemote,
    );
    logger.seek(fromMs: 20, toMs: 1000, source: CommandSource.ui);
    logger.itemChanged(
      oldItemId: 'track-1',
      newItemId: 'track-2',
      reason: 'next',
      source: CommandSource.ui,
    );
    logger.bufferingStarted(itemId: 'track-2', positionMs: 30);
    logger.bufferingEnded(itemId: 'track-2', durationMs: 250);
    logger.interrupted(type: 'pause', itemId: 'track-2', positionMs: 40);
    logger.error(code: 'network', itemId: 'track-2', recoverable: true);
    logger.stopped(itemId: 'track-2', reason: 'user', source: CommandSource.ui);

    expect(events.map((event) => event.name), <String>[
      'player_load_started',
      'player_load_ready',
      'player_play',
      'player_pause',
      'player_seek',
      'player_item_changed',
      'player_buffering_started',
      'player_buffering_ended',
      'player_interrupted',
      'player_error',
      'player_stopped',
    ]);
    expect(events[0].fields, <String, Object?>{
      'itemId': 'track-1',
      'generation': 1,
      'index': 0,
      'source': 'ui',
    });
    expect(events[1].fields, <String, Object?>{
      'itemId': 'track-1',
      'generation': 1,
      'index': 0,
      'durationMs': 2000,
      'latencyMs': 125,
      'source': 'systemRemote',
    });
    expect(
      events[2].fields.keys,
      unorderedEquals(<String>['itemId', 'positionMs', 'source']),
    );
    expect(
      events[3].fields.keys,
      unorderedEquals(<String>['itemId', 'positionMs', 'source']),
    );
    expect(events[4].fields, <String, Object?>{
      'fromMs': 20,
      'toMs': 1000,
      'source': 'ui',
    });
    expect(events[5].fields, <String, Object?>{
      'oldItemId': 'track-1',
      'newItemId': 'track-2',
      'reason': 'next',
      'source': 'ui',
    });
    expect(
      events[6].fields.keys,
      unorderedEquals(<String>['itemId', 'positionMs']),
    );
    expect(
      events[7].fields.keys,
      unorderedEquals(<String>['itemId', 'durationMs']),
    );
    expect(events[8].fields, <String, Object?>{
      'type': 'pause',
      'itemId': 'track-2',
      'positionMs': 40,
      'source': 'interruption',
    });
    expect(events[9].fields, <String, Object?>{
      'code': 'network',
      'itemId': 'track-2',
      'recoverable': true,
    });
    expect(events[10].fields, <String, Object?>{
      'itemId': 'track-2',
      'reason': 'user',
      'source': 'ui',
    });
    expect(
      events.expand((event) => event.fields.keys),
      isNot(anyOf(contains('uri'), contains('title'), contains('artist'))),
    );
  });

  test('logger sink failures are swallowed', () {
    final logger = PlayerLogger((_, _) {
      throw StateError('telemetry unavailable');
    });

    expect(
      () => logger.error(code: 'network', itemId: 'track-1', recoverable: true),
      returnsNormally,
    );
  });

  test(
    'passive interruption observation logs only begin and noisy events',
    () async {
      final interruptions = StreamController<AudioInterruptionEvent>.broadcast(
        sync: true,
      );
      final noisy = StreamController<void>.broadcast(sync: true);
      final snapshots = StreamController<PlaybackSnapshot>.broadcast(
        sync: true,
      );
      final events = <_LogEvent>[];
      final observer = InterruptionObserver(
        interruptionEvents: interruptions.stream,
        becomingNoisyEvents: noisy.stream,
        confirmedSnapshots: snapshots.stream,
        logger: PlayerLogger(
          (event, fields) => events.add(_LogEvent(event, fields)),
        ),
      );
      addTearDown(() async {
        await observer.dispose();
        await interruptions.close();
        await noisy.close();
        await snapshots.close();
      });

      interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      noisy.add(null);

      expect(events.map((event) => event.name), <String>[
        'player_interrupted',
        'player_interrupted',
      ]);
      expect(events[0].fields['type'], 'pause');
      expect(events[0].fields['source'], 'interruption');
      expect(events[1].fields['type'], 'becomingNoisy');
      expect(events[1].fields['source'], 'interruption');
    },
  );

  group('AppAudioHandler logging', () {
    late FakePlaybackEngine engine;
    late FakePlayerClock clock;
    late List<_LogEvent> events;
    late AppAudioHandler handler;

    setUp(() {
      engine = FakePlaybackEngine();
      clock = FakePlayerClock();
      events = <_LogEvent>[];
      handler = _handler(
        engine: engine,
        clock: clock,
        onEvent: (event, fields) => events.add(_LogEvent(event, fields)),
      );
    });

    tearDown(() async {
      await handler.dispose();
    });

    test(
      'load latency, confirmed playback, seek and stop use provenance',
      () async {
        final item = testPlayerItem(id: 'logging-track');
        await _load(handler, engine, clock, [
          item,
        ], latency: const Duration(milliseconds: 125));

        expect(events.map((event) => event.name), <String>[
          'player_load_started',
          'player_load_ready',
          'player_item_changed',
        ]);
        expect(events[1].fields['latencyMs'], 125);
        events.clear();

        final play = handler.handlePlay(CommandSource.ui);
        await pumpEventQueue();
        engine.emitPlayerState(
          just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        );
        await play;
        await pumpEventQueue();

        final pause = handler.handlePause(CommandSource.systemRemote);
        await pumpEventQueue();
        engine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.ready),
        );
        await pause;
        await pumpEventQueue();

        final seek = handler.handleSeek(
          const Duration(seconds: 1),
          CommandSource.ui,
        );
        await seek;
        await pumpEventQueue();

        await handler.handleStop(CommandSource.ui);
        await pumpEventQueue();

        expect(events.map((event) => event.name), <String>[
          'player_play',
          'player_pause',
          'player_seek',
          'player_stopped',
        ]);
        expect(events[0].fields['source'], 'ui');
        expect(events[1].fields['source'], 'systemRemote');
        expect(events[2].fields, <String, Object?>{
          'fromMs': 0,
          'toMs': 1000,
          'source': 'ui',
        });
        expect(events[3].fields, <String, Object?>{
          'itemId': 'logging-track',
          'reason': 'user',
          'source': 'ui',
        });
      },
    );

    test('buffering edge duration is cleared on error', () async {
      final item = testPlayerItem(id: 'buffering-track');
      await _load(handler, engine, clock, [item]);
      events.clear();

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.buffering),
      );
      clock.advance(const Duration(milliseconds: 250));
      engine.emitError(just_audio.PlayerException(0, 'network', 0));
      await pumpEventQueue();

      expect(events.map((event) => event.name), <String>[
        'player_buffering_started',
        'player_buffering_ended',
        'player_error',
      ]);
      expect(events[1].fields['durationMs'], 250);
      expect(events[2].fields, <String, Object?>{
        'code': 'network',
        'itemId': 'buffering-track',
        'recoverable': true,
      });
    });

    test('navigation and engine item changes keep provenance honest', () async {
      final first = testPlayerItem(id: 'first');
      final second = testPlayerItem(
        id: 'second',
        audioUri: Uri.parse('https://example.com/second.mp3'),
      );
      await _load(handler, engine, clock, [first, second]);
      events.clear();

      final next = handler.handleNext(CommandSource.ui);
      await pumpEventQueue();
      engine.emitCurrentIndex(1);
      await next;
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.name, 'player_item_changed');
      expect(events.single.fields, <String, Object?>{
        'oldItemId': 'first',
        'newItemId': 'second',
        'reason': 'next',
        'source': 'ui',
      });

      events.clear();
      engine.emitCurrentIndex(0);
      await pumpEventQueue();
      expect(events.single.fields, <String, Object?>{
        'oldItemId': 'second',
        'newItemId': 'first',
        'reason': 'engine',
      });
    });

    test(
      'failed navigation does not retain provenance for engine advance',
      () async {
        final first = testPlayerItem(id: 'failed-navigation-first');
        final second = testPlayerItem(
          id: 'failed-navigation-second',
          audioUri: Uri.parse(
            'https://example.com/failed-navigation-second.mp3',
          ),
        );
        await _load(handler, engine, clock, [first, second]);
        events.clear();

        final failure = StateError('navigation seek failed');
        engine.seekAction = (_, {index}) => Future<void>.error(failure);

        await expectLater(
          handler.handleNext(CommandSource.ui),
          throwsA(same(failure)),
        );
        engine.emitCurrentIndex(1);
        await pumpEventQueue();

        expect(events, hasLength(1));
        expect(events.single.fields, <String, Object?>{
          'oldItemId': first.id,
          'newItemId': second.id,
          'reason': 'engine',
        });
      },
    );

    test('concurrent Stop emits once using the first source', () async {
      final item = testPlayerItem(id: 'stop-track');
      await _load(handler, engine, clock, [item]);
      events.clear();
      final stopCompletion = Completer<void>();
      engine.stopAction = () => stopCompletion.future;

      final firstStop = handler.handleStop(CommandSource.ui);
      await pumpEventQueue();
      final secondStop = handler.handleStop(CommandSource.systemRemote);
      expect(identical(firstStop, secondStop), isTrue);

      stopCompletion.complete();
      await firstStop;
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.name, 'player_stopped');
      expect(events.single.fields['source'], 'ui');
    });

    test('Stop failure logs error without stopped event', () async {
      final item = testPlayerItem(id: 'failed-stop-track');
      await _load(handler, engine, clock, [item]);
      events.clear();
      engine.stopAction = () => Future<void>.error(StateError('stop failed'));

      await expectLater(
        handler.handleStop(CommandSource.ui),
        throwsA(isA<StateError>()),
      );

      expect(events.map((event) => event.name), ['player_error']);
      expect(events.single.fields, <String, Object?>{
        'code': 'stopFailed',
        'itemId': 'failed-stop-track',
        'recoverable': false,
      });
    });

    test(
      'throwing logger does not change a successful command result',
      () async {
        await handler.dispose();
        engine = FakePlaybackEngine();
        clock = FakePlayerClock();
        handler = _handler(
          engine: engine,
          clock: clock,
          onEvent: (_, _) => throw StateError('telemetry unavailable'),
        );
        final item = testPlayerItem(id: 'throwing-logger-track');
        await _load(handler, engine, clock, [item]);

        final play = handler.handlePlay(CommandSource.ui);
        await pumpEventQueue();
        engine.emitPlayerState(
          just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        );

        await expectLater(play, completes);
        expect(engine.callCountFor('play'), 1);
      },
    );
  });
}

AppAudioHandler _handler({
  required FakePlaybackEngine engine,
  required FakePlayerClock clock,
  required PlayerLogSink onEvent,
}) => AppAudioHandler(
  engine,
  clock,
  null,
  null,
  null,
  null,
  PlayerLogger(onEvent),
);

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  FakePlayerClock clock,
  List items, {
  Duration latency = Duration.zero,
}) async {
  final load = handler.handleLoadQueue(
    items.cast(),
    0,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  final request = engine.loadRequests.last;
  engine.emitDuration(
    const Duration(seconds: 2),
    sourceGeneration: request.sourceGeneration,
  );
  if (latency > Duration.zero) {
    clock.advance(latency);
  }
  request.complete();
  await load;
  await pumpEventQueue();
}

final class _LogEvent {
  const _LogEvent(this.name, this.fields);

  final String name;
  final Map<String, Object?> fields;
}
