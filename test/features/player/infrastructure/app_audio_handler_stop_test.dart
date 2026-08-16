// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late AppAudioHandler handler;

  setUp(() {
    engine = FakePlaybackEngine();
    handler = AppAudioHandler(engine, FakePlayerClock());
  });

  tearDown(() async {
    await handler.dispose();
  });

  Future<PlayerItem> loadActive({required String itemId}) async {
    final item = testPlayerItem(id: itemId);
    final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
    await pumpEventQueue();
    engine.loadRequests.last.complete();
    await load;
    await pumpEventQueue();
    return item;
  }

  Future<void> setState(_StopState state, {required PlayerItem item}) async {
    switch (state) {
      case _StopState.playing:
        engine.emitPlayerState(
          just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        );
      case _StopState.paused:
        engine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.ready),
        );
      case _StopState.loading:
        engine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.loading),
        );
      case _StopState.error:
        engine.emitError(
          just_audio.PlayerException(0, 'Network unavailable', 0),
        );
      case _StopState.completed:
        engine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.completed),
        );
    }
    await pumpEventQueue();
    expect(handler.mediaItem.value?.id, item.id);
  }

  Future<PlaybackSnapshot> latestSnapshot() async {
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    await pumpEventQueue();
    await subscription.cancel();
    return snapshots.last;
  }

  Future<void> pumpUntil(bool Function() condition) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (condition()) {
        return;
      }
      await pumpEventQueue();
    }
    fail(
      'Condition did not become true while pumping the event queue. '
      'Calls: ${engine.calls.map((call) => call.name).toList()}',
    );
  }

  for (final state in <_StopState>[
    _StopState.playing,
    _StopState.paused,
    _StopState.loading,
    _StopState.error,
    _StopState.completed,
  ]) {
    test('successful Stop clears a ${state.name} session', () async {
      final item = await loadActive(itemId: 'stop-${state.name}');
      await setState(state, item: item);

      final snapshots = <PlaybackSnapshot>[];
      final subscription = handler.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      snapshots.clear();

      final stop = handler.handleStop(CommandSource.ui);
      await stop;
      await pumpEventQueue();

      expect(snapshots, [PlaybackSnapshot.idle]);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.idle,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.queueIndex, isNull);
      expect(
        engine.calls.map((call) => call.name),
        containsAllInOrder(<String>[
          'stop',
          'setSpeed',
          'setLoopMode',
          'setShuffleEnabled',
        ]),
      );
    });
  }

  test('Stop publishes system cleanup before one Domain idle snapshot', () async {
    await loadActive(itemId: 'stop-order');
    final callOffset = engine.calls.length;
    final events = <String>[];
    final subscriptions = <StreamSubscription<dynamic>>[
      handler.mediaItem.listen(
        (item) => events.add('mediaItem:${item?.id ?? 'null'}'),
      ),
      handler.queue.listen(
        (items) =>
            events.add('queue:${items.map((item) => item.id).join(',')}'),
      ),
      handler.playbackState.listen(
        (state) => events.add('playbackState:${state.processingState.name}'),
      ),
      handler.snapshots.listen(
        (snapshot) => events.add(
          'snapshot:${snapshot.processingState.name}:${snapshot.currentItem?.id ?? 'null'}',
        ),
      ),
    ];
    addTearDown(() => Future.wait(subscriptions.map((item) => item.cancel())));
    await pumpEventQueue();
    events.clear();

    await handler.handleStop(CommandSource.ui);
    await pumpEventQueue();

    expect(events, <String>[
      'mediaItem:null',
      'queue:',
      'playbackState:idle',
      'snapshot:idle:null',
    ]);
    expect(
      engine.calls
          .sublist(callOffset)
          .map((call) => call.name)
          .toList(growable: false),
      <String>['stop', 'setSpeed', 'setLoopMode', 'setShuffleEnabled'],
    );
  });

  test(
    'engine events inside and after successful Stop cannot revive state',
    () async {
      await loadActive(itemId: 'stop-late-events');
      final mediaEvents = <audio_service.MediaItem?>[];
      final queueEvents = <List<audio_service.MediaItem>>[];
      final playbackEvents = <audio_service.PlaybackState>[];
      final snapshots = <PlaybackSnapshot>[];
      final subscriptions = <StreamSubscription<dynamic>>[
        handler.mediaItem.listen(mediaEvents.add),
        handler.queue.listen(queueEvents.add),
        handler.playbackState.listen(playbackEvents.add),
        handler.snapshots.listen(snapshots.add),
      ];
      addTearDown(
        () => Future.wait(subscriptions.map((item) => item.cancel())),
      );
      await pumpEventQueue();
      mediaEvents.clear();
      queueEvents.clear();
      playbackEvents.clear();
      snapshots.clear();

      engine.stopAction = () {
        engine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.idle),
        );
        engine.emitPosition(const Duration(seconds: 42));
        engine.emitDuration(const Duration(minutes: 4));
        engine.emitCurrentIndex(0);
        engine.emitError(just_audio.PlayerException(0, 'late engine error', 0));
        return Future<void>.value();
      };

      await handler.handleStop(CommandSource.ui);
      await pumpEventQueue();
      mediaEvents.clear();
      queueEvents.clear();
      playbackEvents.clear();
      snapshots.clear();

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      engine.emitPosition(const Duration(seconds: 99));
      engine.emitDuration(const Duration(minutes: 9));
      engine.emitCurrentIndex(0);
      await pumpEventQueue();

      expect(mediaEvents, isEmpty);
      expect(queueEvents, isEmpty);
      expect(playbackEvents, isEmpty);
      expect(snapshots, isEmpty);

      final speedCalls = engine.callCountFor('setSpeed');
      final repeatCalls = engine.callCountFor('setLoopMode');
      final shuffleCalls = engine.callCountFor('setShuffleEnabled');
      final newItem = testPlayerItem(id: 'stop-late-events-new-source');
      final load = handler.handleLoadQueue(
        [newItem],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      engine.loadRequests.last.complete();
      await pumpEventQueue();

      await pumpUntil(() => engine.callCountFor('setSpeed') > speedCalls);
      engine.emitSpeed(1.0);
      await pumpEventQueue();
      await pumpUntil(() => engine.callCountFor('setLoopMode') > repeatCalls);
      engine.emitLoopMode(just_audio.LoopMode.off);
      await pumpEventQueue();
      await pumpUntil(
        () => engine.callCountFor('setShuffleEnabled') > shuffleCalls,
      );
      engine.emitShuffleModeEnabled(false);
      await pumpEventQueue();
      engine.emitEffectiveSequence(const <int>[0]);
      await load;

      expect(handler.mediaItem.value?.id, newItem.id);
      expect(handler.playbackState.value.position, Duration.zero);
      expect(snapshots, isNotEmpty);
      expect(snapshots.last.position, Duration.zero);
      expect(snapshots.last.duration, Duration.zero);
    },
  );

  test(
    'second Stop after success is an engine and publication no-op',
    () async {
      await loadActive(itemId: 'stop-idempotent');
      final mediaEvents = <audio_service.MediaItem?>[];
      final queueEvents = <List<audio_service.MediaItem>>[];
      final playbackEvents = <audio_service.PlaybackState>[];
      final snapshots = <PlaybackSnapshot>[];
      final subscriptions = <StreamSubscription<dynamic>>[
        handler.mediaItem.listen(mediaEvents.add),
        handler.queue.listen(queueEvents.add),
        handler.playbackState.listen(playbackEvents.add),
        handler.snapshots.listen(snapshots.add),
      ];
      addTearDown(
        () => Future.wait(subscriptions.map((item) => item.cancel())),
      );
      await pumpEventQueue();
      mediaEvents.clear();
      queueEvents.clear();
      playbackEvents.clear();
      snapshots.clear();

      await handler.handleStop(CommandSource.ui);
      await pumpEventQueue();
      final calls = engine.calls.length;
      mediaEvents.clear();
      queueEvents.clear();
      playbackEvents.clear();
      snapshots.clear();

      await handler.handleStop(CommandSource.ui);
      await pumpEventQueue();

      expect(engine.calls, hasLength(calls));
      expect(mediaEvents, isEmpty);
      expect(queueEvents, isEmpty);
      expect(playbackEvents, isEmpty);
      expect(snapshots, isEmpty);
    },
  );

  test('concurrent Stops join one transaction', () async {
    await loadActive(itemId: 'stop-concurrent');
    final releaseStop = Completer<void>();
    engine.stopAction = () => releaseStop.future;

    final first = handler.handleStop(CommandSource.ui);
    await pumpEventQueue();
    final second = handler.stop();

    expect(engine.callCountFor('stop'), 1);

    releaseStop.complete();
    await Future.wait<void>([first, second]);
    expect(engine.callCountFor('stop'), 1);
    expect(handler.mediaItem.value, isNull);
  });

  test('Stop without engine idle confirmation retains the session', () async {
    final item = await loadActive(itemId: 'stop-no-confirmation');
    engine.stopAction = () =>
        Future<void>.error(const PlaybackStopNotConfirmed());

    await expectLater(
      handler.handleStop(CommandSource.ui),
      throwsA(isA<PlaybackStopNotConfirmed>()),
    );

    expect(handler.mediaItem.value?.id, item.id);
    expect(handler.queue.value, isNotEmpty);
    expect((await latestSnapshot()).failure?.code, 'stopFailed');
    expect(handler.playbackState.value.errorCode, 1005);
  });

  test(
    'failed Stop drops late events from an invalidated initial load',
    () async {
      await handler.dispose();
      engine = FakePlaybackEngine(interruptCompletesLoad: false);
      handler = AppAudioHandler(engine, FakePlayerClock());

      final item = testPlayerItem(id: 'stop-failed-pending-initial-load');
      final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
      await pumpEventQueue();

      final stopError = StateError('stop failed during initial load');
      engine.stopAction = () => Future<void>.error(stopError);
      await expectLater(
        handler.handleStop(CommandSource.ui),
        throwsA(same(stopError)),
      );

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      engine.emitPosition(const Duration(seconds: 12));
      engine.emitDuration(const Duration(minutes: 3));
      engine.emitCurrentIndex(0);
      engine.loadRequests.single.complete();
      await load;
      await pumpEventQueue();

      final snapshot = await latestSnapshot();
      expect(snapshot.failure?.code, 'stopFailed');
      expect(snapshot.processingState, PlaybackProcessingState.error);
      expect(snapshot.playing, isFalse);
      expect(snapshot.currentItem, isNull);
      expect(snapshot.queue, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
    },
  );

  test(
    'failed Stop fences late events from the retained active source',
    () async {
      await loadActive(itemId: 'stop-failed-active-source');

      final stopError = StateError('stop failed with active source');
      engine.stopAction = () => Future<void>.error(stopError);
      await expectLater(
        handler.handleStop(CommandSource.ui),
        throwsA(same(stopError)),
      );

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        sourceGeneration: 1,
      );
      await pumpEventQueue();

      final snapshot = await latestSnapshot();
      expect(snapshot.failure?.code, 'stopFailed');
      expect(snapshot.processingState, PlaybackProcessingState.error);
      expect(snapshot.playing, isFalse);
      expect(snapshot.currentItem?.id, 'stop-failed-active-source');
    },
  );

  test('failed Stop fences late events from active A and pending B', () async {
    await handler.dispose();
    engine = FakePlaybackEngine(interruptCompletesLoad: false);
    handler = AppAudioHandler(engine, FakePlayerClock());

    await loadActive(itemId: 'stop-failed-active-a');
    final loadB = handler.handleLoadQueue(
      [testPlayerItem(id: 'stop-failed-pending-b')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    final stopError = StateError('stop failed with active and pending source');
    engine.stopAction = () => Future<void>.error(stopError);
    await expectLater(
      handler.handleStop(CommandSource.ui),
      throwsA(same(stopError)),
    );

    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      sourceGeneration: 1,
    );
    engine.emitPosition(const Duration(seconds: 11), sourceGeneration: 1);
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      sourceGeneration: 2,
    );
    engine.emitPosition(const Duration(seconds: 22), sourceGeneration: 2);
    engine.loadRequests.last.complete();
    await loadB;
    await pumpEventQueue();

    final snapshot = await latestSnapshot();
    expect(snapshot.failure?.code, 'stopFailed');
    expect(snapshot.processingState, PlaybackProcessingState.error);
    expect(snapshot.currentItem?.id, 'stop-failed-active-a');
    expect(snapshot.queue.map((item) => item.id), ['stop-failed-active-a']);
    expect(handler.mediaItem.value?.id, 'stop-failed-active-a');
    expect(handler.queue.value.map((item) => item.id), [
      'stop-failed-active-a',
    ]);
  });

  test(
    'successful Stop trusts the engine contract without a source event',
    () async {
      await loadActive(itemId: 'stop-no-source-event');
      engine.emitStopConfirmation = false;

      await handler.handleStop(CommandSource.ui);

      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(await latestSnapshot(), PlaybackSnapshot.idle);
    },
  );

  test('Stop failure ignores state from an older graph generation', () async {
    await loadActive(itemId: 'stop-old-generation');
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    await pumpEventQueue();
    final stopError = StateError('stop failed');
    engine.stopAction = () {
      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
        sourceGeneration: 0,
      );
      return Future<void>.error(stopError);
    };

    await expectLater(
      handler.handleStop(CommandSource.ui),
      throwsA(same(stopError)),
    );

    final snapshot = await latestSnapshot();
    expect(snapshot.failure?.code, 'stopFailed');
    expect(snapshot.playing, isTrue);
  });

  test('Stop failure retains session/card and exposes stopFailed', () async {
    final item = await loadActive(itemId: 'stop-failure');
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    await pumpEventQueue();
    final stopError = StateError('stop failed');
    engine.stopAction = () {
      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      return Future<void>.error(stopError);
    };

    final mediaEvents = <audio_service.MediaItem?>[];
    final queueEvents = <List<audio_service.MediaItem>>[];
    final playbackEvents = <audio_service.PlaybackState>[];
    final snapshots = <PlaybackSnapshot>[];
    final subscriptions = <StreamSubscription<dynamic>>[
      handler.mediaItem.listen(mediaEvents.add),
      handler.queue.listen(queueEvents.add),
      handler.playbackState.listen(playbackEvents.add),
      handler.snapshots.listen(snapshots.add),
    ];
    addTearDown(() => Future.wait(subscriptions.map((item) => item.cancel())));
    await pumpEventQueue();
    mediaEvents.clear();
    queueEvents.clear();
    playbackEvents.clear();
    snapshots.clear();

    await expectLater(
      handler.handleStop(CommandSource.ui),
      throwsA(same(stopError)),
    );
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, item.id);
    expect(handler.queue.value.map((mediaItem) => mediaItem.id), [item.id]);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.failure?.code, 'stopFailed');
    expect(snapshots.single.failure?.isRecoverable, isFalse);
    expect(snapshots.single.playing, isFalse);
    expect(mediaEvents, isEmpty);
    expect(queueEvents, isEmpty);
    expect(playbackEvents, hasLength(1));
    expect(
      playbackEvents.single.processingState,
      audio_service.AudioProcessingState.error,
    );
    expect(handler.playbackState.value.errorCode, 1005);
    expect(
      handler.playbackState.value.processingState,
      audio_service.AudioProcessingState.error,
    );
    expect(handler.mediaItem.value, isNotNull);
    expect(handler.queue.value, isNotEmpty);
  });

  test('Stop after failure retries and can complete cleanup', () async {
    await loadActive(itemId: 'stop-retry');
    var attempts = 0;
    engine.stopAction = () {
      attempts += 1;
      return attempts == 1
          ? Future<void>.error(StateError('first stop failed'))
          : Future<void>.value();
    };

    await expectLater(
      handler.handleStop(CommandSource.ui),
      throwsA(isA<StateError>()),
    );
    expect(handler.mediaItem.value, isNotNull);
    await handler.handleStop(CommandSource.ui);

    expect(attempts, 2);
    expect(handler.mediaItem.value, isNull);
    expect(handler.queue.value, isEmpty);
    expect(await latestSnapshot(), PlaybackSnapshot.idle);
  });

  test(
    'option reset failure still cleans outward and reapplies baseline',
    () async {
      await loadActive(itemId: 'stop-reset-failure');
      engine.setSpeedAction = (_) =>
          Future<void>.error(StateError('speed reset'));

      await handler.handleStop(CommandSource.ui);

      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(engine.callCountFor('setSpeed'), 1);
      expect(engine.callCountFor('setLoopMode'), 1);
      expect(engine.callCountFor('setShuffleEnabled'), 1);

      engine.setSpeedAction = null;
      final newItem = testPlayerItem(id: 'after-stop-reset-failure');
      final speedCalls = engine.callCountFor('setSpeed');
      final repeatCalls = engine.callCountFor('setLoopMode');
      final shuffleCalls = engine.callCountFor('setShuffleEnabled');
      final load = handler.handleLoadQueue(
        [newItem],
        0,
        false,
        CommandSource.ui,
      );
      var loadCompleted = false;
      unawaited(
        load.then<void>(
          (_) => loadCompleted = true,
          onError: (Object _, StackTrace _) => loadCompleted = true,
        ),
      );
      await pumpEventQueue();
      engine.loadRequests.last.complete();
      await pumpEventQueue();

      expect(loadCompleted, isFalse);
      expect(
        handler.playbackState.value.processingState,
        isNot(audio_service.AudioProcessingState.ready),
      );

      await pumpUntil(() => engine.callCountFor('setSpeed') > speedCalls);
      engine.emitSpeed(1.0);
      await pumpEventQueue();
      expect(loadCompleted, isFalse);
      expect(
        handler.playbackState.value.processingState,
        isNot(audio_service.AudioProcessingState.ready),
      );

      await pumpUntil(() => engine.callCountFor('setLoopMode') > repeatCalls);
      engine.emitLoopMode(just_audio.LoopMode.off);
      await pumpEventQueue();
      expect(loadCompleted, isFalse);
      expect(
        handler.playbackState.value.processingState,
        isNot(audio_service.AudioProcessingState.ready),
      );

      await pumpUntil(
        () => engine.callCountFor('setShuffleEnabled') > shuffleCalls,
      );
      engine.emitShuffleModeEnabled(false);
      await pumpEventQueue();
      expect(loadCompleted, isFalse);
      expect(
        handler.playbackState.value.processingState,
        isNot(audio_service.AudioProcessingState.ready),
      );
      engine.emitEffectiveSequence(const <int>[0]);
      await load;
      expect(loadCompleted, isTrue);

      expect(handler.mediaItem.value?.id, newItem.id);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.ready,
      );
      final names = engine.calls.map((call) => call.name).toList();
      expect(names, contains('setSpeed'));
      expect(names, contains('setLoopMode'));
      expect(names, contains('setShuffleEnabled'));
    },
  );

  for (final option in <_StopResetOption>[
    _StopResetOption.repeat,
    _StopResetOption.shuffle,
  ]) {
    test('Stop survives ${option.name} reset failure', () async {
      await loadActive(itemId: 'stop-${option.name}-reset-failure');
      final failure = StateError('${option.name} reset');
      switch (option) {
        case _StopResetOption.repeat:
          engine.setLoopModeAction = (_) => Future<void>.error(failure);
        case _StopResetOption.shuffle:
          engine.setShuffleEnabledAction = (_) => Future<void>.error(failure);
      }

      await handler.handleStop(CommandSource.ui);

      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.idle,
      );
      expect(engine.callCountFor('setSpeed'), 1);
      expect(engine.callCountFor('setLoopMode'), 1);
      expect(engine.callCountFor('setShuffleEnabled'), 1);
    });
  }

  test('multiple option reset failures do not fail successful Stop', () async {
    await loadActive(itemId: 'stop-multiple-reset-failures');
    engine.setSpeedAction = (_) =>
        Future<void>.error(StateError('speed reset'));
    engine.setLoopModeAction = (_) =>
        Future<void>.error(StateError('repeat reset'));
    engine.setShuffleEnabledAction = (_) =>
        Future<void>.error(StateError('shuffle reset'));

    await handler.handleStop(CommandSource.ui);

    expect(handler.mediaItem.value, isNull);
    expect(handler.queue.value, isEmpty);
    expect(
      handler.playbackState.value.processingState,
      audio_service.AudioProcessingState.idle,
    );
    expect(engine.callCountFor('setSpeed'), 1);
    expect(engine.callCountFor('setLoopMode'), 1);
    expect(engine.callCountFor('setShuffleEnabled'), 1);
  });

  test(
    'pending load is invalidated and late success cannot revive after Stop',
    () async {
      engine = FakePlaybackEngine(interruptCompletesLoad: false);
      await handler.dispose();
      handler = AppAudioHandler(engine, FakePlayerClock());
      final item = testPlayerItem(id: 'late-load');
      final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
      await pumpEventQueue();

      final stop = handler.handleStop(CommandSource.ui);
      await stop;
      engine.loadRequests.single.complete();
      await load;
      await pumpEventQueue();

      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(await latestSnapshot(), PlaybackSnapshot.idle);
    },
  );

  test(
    'late error from an invalidated load cannot create a failure after Stop',
    () async {
      engine = FakePlaybackEngine(interruptCompletesLoad: false);
      await handler.dispose();
      handler = AppAudioHandler(engine, FakePlayerClock());

      final snapshots = <PlaybackSnapshot>[];
      final playbackEvents = <audio_service.PlaybackState>[];
      final subscriptions = <StreamSubscription<dynamic>>[
        handler.playbackState.listen(playbackEvents.add),
        handler.snapshots.listen(snapshots.add),
      ];
      addTearDown(
        () => Future.wait(subscriptions.map((item) => item.cancel())),
      );
      await pumpEventQueue();
      playbackEvents.clear();
      snapshots.clear();

      final item = testPlayerItem(id: 'late-load-error');
      final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
      await pumpEventQueue();
      final stop = handler.handleStop(CommandSource.ui);
      await stop;
      await pumpEventQueue();
      playbackEvents.clear();
      snapshots.clear();

      engine.loadRequests.single.completeError(StateError('late load error'));
      await load;
      await pumpEventQueue();

      expect(playbackEvents, isEmpty);
      expect(snapshots, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(handler.playbackState.value.errorCode, isNull);
    },
  );

  test('Stop sees a load submitted before its transaction starts', () async {
    final item = testPlayerItem(id: 'queued-before-stop');
    final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
    final stop = handler.handleStop(CommandSource.ui);

    await stop;
    await load;

    expect(engine.callCountFor('load'), 0);
    expect(engine.callCountFor('stop'), 1);
    expect(handler.mediaItem.value, isNull);
    expect(handler.queue.value, isEmpty);
    expect(await latestSnapshot(), PlaybackSnapshot.idle);
  });

  test(
    'late old-source events after new load starts cannot contaminate pending source',
    () async {
      await loadActive(itemId: 'old-source');
      await handler.handleStop(CommandSource.ui);

      final newItem = testPlayerItem(id: 'new-source');
      final speedCalls = engine.callCountFor('setSpeed');
      final repeatCalls = engine.callCountFor('setLoopMode');
      final shuffleCalls = engine.callCountFor('setShuffleEnabled');
      final load = handler.handleLoadQueue(
        [newItem],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      // Generation 1 is the source that was stopped. Generation 2 is now
      // pending, so these events must not enter its accumulator.
      engine.emitPosition(const Duration(seconds: 99), sourceGeneration: 1);
      engine.emitBufferedPosition(
        const Duration(seconds: 98),
        sourceGeneration: 1,
      );
      engine.emitDuration(const Duration(minutes: 9), sourceGeneration: 1);
      engine.emitCurrentIndex(0, sourceGeneration: 1);

      engine.loadRequests.last.complete();
      await pumpEventQueue();

      await pumpUntil(() => engine.callCountFor('setSpeed') > speedCalls);
      engine.emitSpeed(1.0);
      await pumpEventQueue();
      await pumpUntil(() => engine.callCountFor('setLoopMode') > repeatCalls);
      engine.emitLoopMode(just_audio.LoopMode.off);
      await pumpEventQueue();
      await pumpUntil(
        () => engine.callCountFor('setShuffleEnabled') > shuffleCalls,
      );
      engine.emitShuffleModeEnabled(false);
      await pumpEventQueue();
      engine.emitEffectiveSequence(const <int>[0]);
      await load;

      final snapshot = await latestSnapshot();
      expect(snapshot.currentItem?.id, newItem.id);
      expect(snapshot.position, Duration.zero);
      expect(snapshot.bufferedPosition, Duration.zero);
      expect(snapshot.duration, Duration.zero);
    },
  );

  test(
    'remote Stop uses system provenance and removes the system card',
    () async {
      final observed = <({String command, CommandSource source})>[];
      await handler.dispose();
      engine = FakePlaybackEngine();
      handler = AppAudioHandler(
        engine,
        FakePlayerClock(),
        (command, source) => observed.add((command: command, source: source)),
      );
      // Recreate the committed session on the new handler used for provenance.
      final item = testPlayerItem(id: 'remote-stop-recreated');
      final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
      await pumpEventQueue();
      engine.loadRequests.last.complete();
      await load;

      await handler.stop();

      expect(observed, [
        (command: 'loadQueue', source: CommandSource.ui),
        (command: 'stop', source: CommandSource.systemRemote),
      ]);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.idle,
      );
    },
  );

  test('commands cannot compete with the active Stop barrier', () async {
    await loadActive(itemId: 'stop-command-barrier');
    final releaseStop = Completer<void>();
    engine.stopAction = () => releaseStop.future;
    final stop = handler.handleStop(CommandSource.ui);
    await pumpEventQueue();

    await expectLater(
      handler.handleSetSpeed(1.5, CommandSource.ui),
      throwsA(isA<PlayerCommandFailure>()),
    );
    expect(engine.callCountFor('setSpeed'), 0);

    releaseStop.complete();
    await stop;
  });
}

enum _StopState { playing, paused, loading, error, completed }

enum _StopResetOption { repeat, shuffle }
