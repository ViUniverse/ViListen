// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/player_failure_mapper.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late AppAudioHandler handler;

  setUp(() {
    engine = FakePlaybackEngine();
    handler = AppAudioHandler(
      engine,
      FakePlayerClock(),
      null,
      null,
      null,
      () => PlayerFailurePlatform.android,
    );
  });

  tearDown(() => handler.dispose());

  test(
    'initial retry loads, clamps, seeks, then commits before playing',
    () async {
      final item = testPlayerItem(id: 'initial');
      await _failInitialLoad(handler, engine, item, autoplay: true);
      final seek = Completer<void>();
      engine.seekAction = (_, {int? index}) => seek.future;

      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.loadRequests.last.initialIndex, 0);
      expect(handler.mediaItem.value, isNull);

      engine.emitDuration(const Duration(seconds: 10));
      engine.loadRequests.last.complete();
      await pumpEventQueue();
      expect(engine.callCountFor('seek'), 1);
      expect(engine.calls.last.name, 'seek');
      expect(handler.mediaItem.value, isNull);

      seek.complete();
      await retry;
      await pumpEventQueue();
      expect(handler.mediaItem.value?.id, item.id);
      expect(engine.calls.map((call) => call.name).takeLast(3), [
        'load',
        'seek',
        'play',
      ]);
      expect(handler.playbackState.value.playing, isFalse);
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      expect(handler.playbackState.value.playing, isTrue);
    },
  );

  test(
    'runtime retry restores a clamped saved position without playing paused intent',
    () async {
      final item = testPlayerItem(id: 'runtime');
      await _load(handler, engine, item);
      engine.emitPosition(const Duration(seconds: 37));
      engine.emitError(just_audio.PlayerException(0, 'Network unavailable', 0));
      await pumpEventQueue();

      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      engine.emitDuration(const Duration(seconds: 20));
      engine.loadRequests.last.complete();
      await retry;

      final seek = engine.calls.lastWhere((call) => call.name == 'seek');
      expect(seek.arguments['position'], const Duration(seconds: 20));
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 20),
      );
      expect(engine.callCountFor('play'), 0);
    },
  );

  test(
    'unknown retry duration seeks zero exactly once before commit',
    () async {
      final item = testPlayerItem(id: 'unknown-duration');
      await _load(handler, engine, item);
      engine.emitPosition(const Duration(seconds: 7));
      engine.emitError(just_audio.PlayerException(0, 'Network unavailable', 0));
      await pumpEventQueue();

      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      engine.loadRequests.last.complete();
      await retry;

      final seek = engine.calls.lastWhere((call) => call.name == 'seek');
      expect(seek.arguments['position'], Duration.zero);
      expect(seek.arguments['index'], 0);
      expect(engine.callCountFor('seek'), 1);
    },
  );

  test(
    'replace retry selects failed B while outward A remains until seek',
    () async {
      final itemA = testPlayerItem(id: 'active-a');
      final itemB = testPlayerItem(id: 'retry-b');
      await _load(handler, engine, itemA);
      await _failLoad(handler, engine, itemB, autoplay: false);
      expect(handler.mediaItem.value?.id, itemA.id);

      final seek = Completer<void>();
      engine.seekAction = (_, {int? index}) => seek.future;
      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.graphItemIds, [itemB.id]);
      engine.emitDuration(const Duration(seconds: 12));
      engine.loadRequests.last.complete();
      await pumpEventQueue();
      expect(handler.mediaItem.value?.id, itemA.id);
      seek.complete();
      await retry;
      expect(handler.mediaItem.value?.id, itemB.id);
    },
  );

  test(
    'retry preserves the exact multi-item target queue and logical index',
    () async {
      final itemA = testPlayerItem(id: 'queue-a');
      final itemB = testPlayerItem(id: 'queue-b');
      final itemC = testPlayerItem(id: 'queue-c');
      final load = handler.handleLoadQueue(
        [itemA, itemB, itemC],
        1,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      final failure = just_audio.PlayerException(0, 'Network unavailable', 0);
      engine.loadRequests.last.completeError(failure);
      await expectLater(load, throwsA(same(failure)));

      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.graphItemIds, [itemA.id, itemB.id, itemC.id]);
      expect(engine.loadRequests.last.initialIndex, 1);
      engine.emitDuration(const Duration(seconds: 10));
      engine.loadRequests.last.complete();
      await retry;

      final seek = engine.calls.lastWhere((call) => call.name == 'seek');
      expect(seek.arguments['index'], 1);
      expect(handler.mediaItem.value?.id, itemB.id);
      expect(handler.playbackState.value.queueIndex, 1);
    },
  );

  test(
    'repeat changed while retry seek is pending is prepared before commit',
    () async {
      final itemA = testPlayerItem(id: 'active-option-a');
      final itemB = testPlayerItem(id: 'retry-option-b');
      await _load(handler, engine, itemA);
      await _failLoad(handler, engine, itemB, autoplay: false);
      final seek = Completer<void>();
      engine.seekAction = (_, {int? index}) => seek.future;

      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      engine.emitDuration(const Duration(seconds: 10));
      engine.loadRequests.last.complete();
      await pumpEventQueue();
      expect(handler.mediaItem.value?.id, itemA.id);

      final setRepeat = handler.handleSetRepeatMode(
        PlayerRepeatMode.one,
        CommandSource.ui,
      );
      engine.emitLoopMode(just_audio.LoopMode.one);
      await setRepeat;
      await pumpEventQueue();
      expect(handler.mediaItem.value?.id, itemA.id);
      seek.complete();
      await retry;

      expect(handler.mediaItem.value?.id, itemB.id);
      expect(
        handler.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.one,
      );
      expect(handler.playbackState.value.errorCode, isNull);
    },
  );

  test(
    'Play and Pause mutate retry desired intent and duplicate retry coalesces',
    () async {
      final item = testPlayerItem(id: 'intent');
      await _failInitialLoad(handler, engine, item, autoplay: false);

      final first = handler.handleRetry(CommandSource.ui);
      final duplicate = handler.handleRetry(CommandSource.ui);
      expect(identical(first, duplicate), isTrue);
      await pumpEventQueue();
      await handler.handlePlay(CommandSource.ui);
      await handler.handlePause(CommandSource.ui);
      engine.emitDuration(const Duration(seconds: 10));
      engine.loadRequests.last.complete();
      await first;

      expect(engine.callCountFor('load'), 2);
      expect(engine.callCountFor('play'), 0);
    },
  );

  test(
    'Play during retry overrides a saved paused intent exactly once',
    () async {
      final item = testPlayerItem(id: 'play-override');
      await _failInitialLoad(handler, engine, item, autoplay: false);

      final retry = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      await handler.handlePlay(CommandSource.ui);
      engine.emitDuration(const Duration(seconds: 10));
      engine.loadRequests.last.complete();
      await retry;
      await pumpEventQueue();

      expect(engine.callCountFor('play'), 1);
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'retry load and seek failures refresh the recoverable retry context',
    () async {
      final item = testPlayerItem(id: 'fails-again');
      await _failInitialLoad(handler, engine, item, autoplay: true);
      final firstContext = handler.retryContext!;

      final retryLoad = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      final loadError = just_audio.PlayerException(0, 'Network unavailable', 0);
      engine.loadRequests.last.completeError(loadError);
      await expectLater(retryLoad, throwsA(same(loadError)));
      expect(handler.retryContext, isNot(same(firstContext)));
      expect(handler.retryContext?.desiredPlaying, isTrue);

      engine.seekAction = (_, {int? index}) => Future<void>.error(
        just_audio.PlayerException(0, 'Network unavailable', 0),
      );
      final retrySeek = handler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      engine.emitDuration(const Duration(seconds: 10));
      engine.loadRequests.last.complete();
      await expectLater(retrySeek, throwsA(isA<just_audio.PlayerException>()));
      expect(handler.retryContext?.failureGeneration, isNotNull);
      expect(handler.retryContext?.restorePosition, Duration.zero);
      expect(handler.retryContext?.failureItemId, item.id);
    },
  );

  test(
    'new load invalidates retry and a late retry result cannot publish',
    () async {
      final staleEngine = FakePlaybackEngine(interruptCompletesLoad: false);
      final staleHandler = AppAudioHandler(
        staleEngine,
        FakePlayerClock(),
        null,
        null,
        null,
        () => PlayerFailurePlatform.android,
      );
      addTearDown(staleHandler.dispose);
      final itemA = testPlayerItem(id: 'stale-retry');
      final itemB = testPlayerItem(id: 'new-load');
      await _failInitialLoad(staleHandler, staleEngine, itemA, autoplay: false);

      final retry = staleHandler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      final staleRequest = staleEngine.loadRequests.last;
      final loadB = staleHandler.handleLoadQueue(
        [itemB],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      await retry;
      staleEngine.loadRequests.last.complete();
      await loadB;
      staleRequest.complete();
      await pumpEventQueue();

      expect(staleHandler.mediaItem.value?.id, itemB.id);
      expect(staleHandler.retryContext, isNull);
    },
  );

  test(
    'active navigation invalidates retry and ignores its late error',
    () async {
      final navigationEngine = FakePlaybackEngine(
        interruptCompletesLoad: false,
      );
      final navigationHandler = AppAudioHandler(
        navigationEngine,
        FakePlayerClock(),
        null,
        null,
        null,
        () => PlayerFailurePlatform.android,
      );
      addTearDown(navigationHandler.dispose);
      final itemA = testPlayerItem(id: 'navigation-a');
      final itemB = testPlayerItem(id: 'navigation-b');
      final initial = navigationHandler.handleLoadQueue(
        [itemA, itemB],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      navigationEngine.loadRequests.last.complete();
      await initial;
      navigationEngine.emitError(
        just_audio.PlayerException(0, 'Network unavailable', 0),
      );
      await pumpEventQueue();

      final retry = navigationHandler.handleRetry(CommandSource.ui);
      await pumpEventQueue();
      final staleRetry = navigationEngine.loadRequests.last;
      final next = navigationHandler.handleNext(CommandSource.ui);
      await pumpEventQueue();
      await retry;
      navigationEngine.emitEffectiveSequence([0, 1]);
      navigationEngine.loadRequests.last.complete();
      await next;
      staleRetry.completeError(
        just_audio.PlayerException(0, 'Network unavailable', 0),
      );
      await pumpEventQueue();

      expect(navigationHandler.retryContext, isNull);
      expect(navigationHandler.playbackState.value.errorCode, isNull);
    },
  );

  test(
    'unavailable retry has stable typed failure and no engine work',
    () async {
      final calls = engine.calls.length;
      await expectLater(
        handler.handleRetry(CommandSource.ui),
        throwsA(
          const PlayerCommandFailure(
            code: 'retryUnavailable',
            message: 'Retry is unavailable.',
            command: 'retry',
          ),
        ),
      );
      expect(engine.calls, hasLength(calls));
    },
  );
}

extension on Iterable<String> {
  Iterable<String> takeLast(int count) => skip(length - count);
}

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  PlayerItem item,
) async {
  final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
  await pumpEventQueue();
  engine.loadRequests.last.complete();
  await load;
  await pumpEventQueue();
}

Future<void> _failInitialLoad(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  PlayerItem item, {
  required bool autoplay,
}) => _failLoad(handler, engine, item, autoplay: autoplay);

Future<void> _failLoad(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  PlayerItem item, {
  required bool autoplay,
}) async {
  final load = handler.handleLoadQueue([item], 0, autoplay, CommandSource.ui);
  await pumpEventQueue();
  final error = just_audio.PlayerException(0, 'Network unavailable', 0);
  engine.loadRequests.last.completeError(error);
  await expectLater(load, throwsA(same(error)));
  await pumpEventQueue();
}
