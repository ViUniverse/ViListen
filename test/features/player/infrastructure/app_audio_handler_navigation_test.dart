// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late AppAudioHandler handler;
  late List<({String command, CommandSource source})> observedCommands;

  setUp(() {
    engine = FakePlaybackEngine();
    observedCommands = <({String command, CommandSource source})>[];
    handler = AppAudioHandler(
      engine,
      FakePlayerClock(),
      (command, source) =>
          observedCommands.add((command: command, source: source)),
    );
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('UI and OS next share one operation and use queue boundaries', () async {
    final items = _items(3);
    await _loadWith(handler, engine, items);
    observedCommands.clear();

    await handler.handleNext(CommandSource.ui);
    engine.emitCurrentIndex(1);
    await handler.skipToNext();
    engine.emitCurrentIndex(2);
    await handler.handleNext(CommandSource.ui);
    await handler.handlePrevious(CommandSource.ui);

    expect(_seekIndexes(engine), [1, 2, 1]);
    expect(observedCommands, [
      (command: 'next', source: CommandSource.ui),
      (command: 'next', source: CommandSource.systemRemote),
      (command: 'next', source: CommandSource.ui),
      (command: 'previous', source: CommandSource.ui),
    ]);
    expect(engine.callCountFor('load'), 1);
    expect(engine.callCountFor('stop'), 0);
  });

  test('repeat all wraps next at the end and previous at the start', () async {
    final items = _items(3);
    await _loadWith(
      handler,
      engine,
      items,
      initialIndex: 2,
      loopMode: just_audio.LoopMode.all,
    );

    await handler.handleNext(CommandSource.ui);
    expect(_lastSeekIndex(engine), 0);
    engine.emitCurrentIndex(0);

    await handler.handlePrevious(CommandSource.ui);
    expect(_lastSeekIndex(engine), 2);
    expect(_seekIndexes(engine), [0, 2]);
  });

  test('repeat off and repeat one are no-ops at the boundary', () async {
    final items = _items(2);
    await _loadWith(handler, engine, items, initialIndex: 1);

    await handler.handleNext(CommandSource.ui);
    expect(_seekIndexes(engine), isEmpty);

    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    await handler.handleNext(CommandSource.ui);
    expect(_seekIndexes(engine), isEmpty);
  });

  test(
    'explicit next is not blocked by repeat one when a next item exists',
    () async {
      final items = _items(3);
      await _loadWith(
        handler,
        engine,
        items,
        initialIndex: 1,
        loopMode: just_audio.LoopMode.one,
      );

      await handler.handleNext(CommandSource.ui);

      expect(_lastSeekIndex(engine), 2);
    },
  );

  test('previous over three seconds restarts the current item', () async {
    final items = _items(3);
    await _loadWith(
      handler,
      engine,
      items,
      initialIndex: 1,
      position: const Duration(seconds: 3, milliseconds: 1),
    );

    await handler.handlePrevious(CommandSource.ui);

    expect(_lastSeekIndex(engine), isNull);
    expect(_lastSeekPosition(engine), Duration.zero);
  });

  test(
    'previous at exactly three seconds navigates to effective previous',
    () async {
      final items = _items(3);
      await _loadWith(
        handler,
        engine,
        items,
        initialIndex: 1,
        position: const Duration(seconds: 3),
      );

      await handler.handlePrevious(CommandSource.ui);

      expect(_lastSeekIndex(engine), 0);
    },
  );

  test(
    'previous below three seconds respects repeat-all wrap and off no-op',
    () async {
      final items = _items(3);
      await _loadWith(
        handler,
        engine,
        items,
        initialIndex: 0,
        position: const Duration(seconds: 2, milliseconds: 999),
        loopMode: just_audio.LoopMode.all,
      );

      await handler.handlePrevious(CommandSource.ui);
      expect(_lastSeekIndex(engine), 2);

      final offEngine = FakePlaybackEngine();
      final offHandler = AppAudioHandler(offEngine, FakePlayerClock());
      addTearDown(offHandler.dispose);
      await _loadWith(
        offHandler,
        offEngine,
        items,
        position: const Duration(seconds: 2),
      );
      await offHandler.handlePrevious(CommandSource.ui);
      expect(offEngine.callCountFor('seek'), 0);
    },
  );

  test(
    'switching item is serialized ahead of a later load without overlap',
    () async {
      final items = _items(2);
      await _loadWith(handler, engine, items);

      final seekCompleter = Completer<void>();
      engine.seekAction = (_, {index}) => seekCompleter.future;
      final next = handler.handleNext(CommandSource.ui);
      await pumpEventQueue();

      final replacement = testPlayerItem(id: 'replacement');
      final load = handler.handleLoadQueue(
        [replacement],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      expect(engine.calls.map((call) => call.name), ['load', 'seek']);

      seekCompleter.complete();
      await next;
      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(2));

      engine.loadRequests.last.complete();
      await load;
      expect(engine.calls.map((call) => call.name), ['load', 'seek', 'load']);
      expect(engine.callCountFor('stop'), 0);
    },
  );

  test(
    'pending engine events stay out of the active snapshot during interrupt',
    () async {
      final activeItems = _items(2);
      await _loadWith(handler, engine, activeItems);

      final pendingItem = testPlayerItem(id: 'pending-track');
      final pendingLoad = handler.handleLoadQueue(
        [pendingItem],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      final navigation = handler.handleNext(CommandSource.ui);
      // This is the ordering exposed by an interrupting engine: the event is
      // delivered after navigation invalidates the generation but before the
      // coordinator reaches the navigation transaction callback.
      engine.emitCurrentIndex(null);

      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(3));
      engine.emitEffectiveSequence([0, 1]);
      engine.loadRequests.last.complete();
      await navigation;
      await pendingLoad;
      await pumpEventQueue();

      expect(engine.graphItemIds, [activeItems[0].id, activeItems[1].id]);
      expect(_seekIndexes(engine), [0, 1]);
      expect(handler.mediaItem.value?.id, activeItems.first.id);
      expect(handler.queue.value.map((item) => item.id), [
        activeItems[0].id,
        activeItems[1].id,
      ]);
    },
  );

  test(
    'boundary navigation restores a pending replacement without navigation seek',
    () async {
      final activeItem = testPlayerItem(id: 'single-active');
      await _loadWith(handler, engine, [activeItem], autoplay: true);

      final pendingItem = testPlayerItem(id: 'boundary-pending');
      final pendingLoad = handler.handleLoadQueue(
        [pendingItem],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      final navigation = handler.handleNext(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(3));
      engine.emitEffectiveSequence([0]);
      engine.loadRequests.last.complete();
      await navigation;
      await pendingLoad;
      await pumpEventQueue();

      expect(engine.callCountFor('interruptLoad'), 1);
      expect(engine.callCountFor('load'), 3);
      expect(engine.graphItemIds, [activeItem.id]);
      expect(engine.callCountFor('seek'), 1);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.ready,
      );
      expect(handler.playbackState.value.playing, isFalse);
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value?.id, activeItem.id);
      expect(handler.queue.value.map((item) => item.id), [activeItem.id]);
    },
  );

  test(
    'a newer source interrupts restore and prevents stale navigation',
    () async {
      final activeItems = _items(2);
      await _loadWith(handler, engine, activeItems);

      final pendingLoad = handler.handleLoadQueue(
        [testPlayerItem(id: 'pending-track')],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      final navigation = handler.handleNext(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(3));

      final replacement = testPlayerItem(id: 'replacement-track');
      final replacementLoad = handler.handleLoadQueue(
        [replacement],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      expect(engine.callCountFor('interruptLoad'), 2);
      expect(engine.loadRequests, hasLength(4));
      engine.loadRequests.last.complete();

      await navigation;
      await pendingLoad;
      await replacementLoad;
      await pumpEventQueue();

      expect(engine.graphItemIds, [replacement.id]);
      expect(engine.callCountFor('seek'), 0);
      expect(handler.mediaItem.value?.id, replacement.id);
      expect(handler.queue.value.map((item) => item.id), [replacement.id]);
    },
  );

  test('restore commits the engine-confirmed effective order', () async {
    final activeItems = _items(3);
    await _loadWith(handler, engine, activeItems, effectiveSequence: [2, 0, 1]);

    final pendingLoad = handler.handleLoadQueue(
      [testPlayerItem(id: 'pending-track')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    final navigation = handler.handleNext(CommandSource.ui);
    await pumpEventQueue();
    expect(engine.loadRequests, hasLength(3));
    engine.emitEffectiveSequence([1, 2, 0]);
    engine.loadRequests.last.complete();

    await navigation;
    await pendingLoad;
    await pumpEventQueue();

    expect(handler.queue.value.map((item) => item.id), [
      activeItems[1].id,
      activeItems[2].id,
      activeItems[0].id,
    ]);
    expect(handler.mediaItem.value?.id, activeItems[0].id);
    expect(handler.playbackState.value.queueIndex, 2);
    expect(_seekIndexes(engine), [0, 1]);

    await handler.handleNext(CommandSource.ui);
    expect(_lastSeekIndex(engine), 1);
  });

  test(
    'restore play failure stays paused until a player-state confirmation',
    () async {
      var playCalls = 0;
      engine.playAction = () {
        playCalls += 1;
        if (playCalls == 2) {
          return Future<void>.error(StateError('restore play failed'));
        }
        return Future<void>.value();
      };

      final activeItem = testPlayerItem(id: 'playing-active');
      await _loadWith(handler, engine, [activeItem], autoplay: true);

      final pendingLoad = handler.handleLoadQueue(
        [testPlayerItem(id: 'pending-track')],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      final navigation = handler.handleNext(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(3));
      engine.emitEffectiveSequence([0]);
      engine.loadRequests.last.complete();

      await navigation;
      await pendingLoad;
      await pumpEventQueue();

      expect(playCalls, 2);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.ready,
      );
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test(
    'navigation follows the engine-confirmed shuffle effective order',
    () async {
      final items = _items(3);
      final snapshots = <PlaybackSnapshot>[];
      final subscription = handler.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await _loadWith(
        handler,
        engine,
        items,
        initialIndex: 0,
        loopMode: just_audio.LoopMode.off,
        effectiveSequence: [2, 0, 1],
      );

      expect(snapshots.last.queue, [items[2], items[0], items[1]]);
      expect(snapshots.last.currentItem, items[0]);
      expect(snapshots.last.currentIndex, 1);
      expect(handler.queue.value.map((item) => item.id), [
        items[2].id,
        items[0].id,
        items[1].id,
      ]);
      expect(handler.playbackState.value.queueIndex, 1);

      await handler.handleNext(CommandSource.ui);
      expect(_lastSeekIndex(engine), 1);
      engine.emitCurrentIndex(1);

      await handler.handlePrevious(CommandSource.ui);
      expect(_lastSeekIndex(engine), 0);
    },
  );
}

Future<void> _loadWith(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  List<PlayerItem> items, {
  int initialIndex = 0,
  Duration position = Duration.zero,
  just_audio.LoopMode loopMode = just_audio.LoopMode.off,
  List<int>? effectiveSequence,
  bool autoplay = false,
}) async {
  final load = handler.handleLoadQueue(
    items,
    initialIndex,
    autoplay,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.loadRequests.last.complete();
  engine.emitPosition(position);
  engine.emitLoopMode(loopMode);
  if (effectiveSequence != null) {
    engine.emitEffectiveSequence(effectiveSequence);
  }
  await load;
  await pumpEventQueue();
}

List<int?> _seekIndexes(FakePlaybackEngine engine) => engine.calls
    .where((call) => call.name == 'seek')
    .map((call) => call.arguments['index'] as int?)
    .toList();

int? _lastSeekIndex(FakePlaybackEngine engine) => _seekIndexes(engine).last;

Duration _lastSeekPosition(FakePlaybackEngine engine) =>
    engine.calls.where((call) => call.name == 'seek').last.arguments['position']
        as Duration;

List<PlayerItem> _items(int count) => List<PlayerItem>.generate(
  count,
  (index) => testPlayerItem(id: 'track-$index'),
);
