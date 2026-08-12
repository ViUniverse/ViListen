// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
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

  test(
    'replays completed item in seek-then-play order and waits for confirmation',
    () async {
      final item = testPlayerItem(id: 'replay-track');
      final publications = await _listenToPublications(handler);
      await _load(handler, engine, [item]);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.completed),
      );
      await pumpEventQueue();
      expect(
        publications.snapshots.last.processingState,
        PlaybackProcessingState.completed,
      );
      expect(publications.snapshots.last.playing, isFalse);
      publications.clear();

      final replay = handler.handlePlay(CommandSource.ui);
      await replay;
      await pumpEventQueue();

      expect(engine.callCountFor('seek'), 1);
      expect(engine.callCountFor('play'), 1);
      expect(engine.calls.last.name, 'play');
      final seekCall = engine.calls.singleWhere((call) => call.name == 'seek');
      expect(seekCall.arguments['position'], Duration.zero);
      expect(seekCall.arguments['index'], 0);
      expect(observedCommands.where((entry) => entry.command == 'play'), [
        (command: 'play', source: CommandSource.ui),
      ]);

      // Calling engine.play() is not itself playback confirmation.
      expect(publications.snapshots, isEmpty);
      expect(publications.playbackStates, isEmpty);
      expect(publications.mediaItems, isEmpty);
      expect(publications.queues, isEmpty);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.completed,
      );
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.mediaItem.value?.id, item.id);
      expect(handler.queue.value.map((mediaItem) => mediaItem.id), [item.id]);

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      expect(publications.snapshots, hasLength(1));
      expect(
        publications.snapshots.single.processingState,
        PlaybackProcessingState.ready,
      );
      expect(publications.snapshots.single.playing, isTrue);
      expect(publications.playbackStates, hasLength(1));
      expect(publications.playbackStates.single.playing, isTrue);
      expect(publications.mediaItems, isEmpty);
      expect(publications.queues, isEmpty);
    },
  );

  test('seek failure prevents Play and preserves completed state', () async {
    final item = testPlayerItem(id: 'seek-failure-track');
    await _load(handler, engine, [item]);
    await _completeCurrentItem(engine);

    final failure = StateError('seek rejected');
    engine.seekAction = (_, {index}) => Future<void>.error(failure);

    await expectLater(
      handler.handlePlay(CommandSource.ui),
      throwsA(same(failure)),
    );

    expect(engine.callCountFor('seek'), 1);
    expect(engine.callCountFor('play'), 0);
    expect(handler.mediaItem.value?.id, item.id);
    expect(handler.queue.value.map((mediaItem) => mediaItem.id), [item.id]);
    expect(
      handler.playbackState.value.processingState,
      audio_service.AudioProcessingState.completed,
    );
    expect(handler.playbackState.value.playing, isFalse);
  });

  test(
    'Replay seeks the logical item when the effective queue is shuffled',
    () async {
      final items = List<PlayerItem>.generate(
        3,
        (index) => testPlayerItem(id: 'shuffle-replay-$index'),
      );
      await _load(handler, engine, items, effectiveSequence: [2, 0, 1]);
      expect(handler.playbackState.value.queueIndex, 1);
      expect(handler.mediaItem.value?.id, items[0].id);

      await _completeCurrentItem(engine);
      await handler.handlePlay(CommandSource.ui);

      final seek = engine.calls.singleWhere((call) => call.name == 'seek');
      expect(seek.arguments['index'], 0);
      expect(engine.callCountFor('play'), 1);
    },
  );

  test('Play failure does not leave the coordinator stuck', () async {
    final item = testPlayerItem(id: 'play-failure-track');
    await _load(handler, engine, [item]);
    await _completeCurrentItem(engine);

    final failure = StateError('play rejected');
    var rejectPlay = true;
    engine.playAction = () =>
        rejectPlay ? Future<void>.error(failure) : Future<void>.value();

    await expectLater(
      handler.handlePlay(CommandSource.ui),
      throwsA(same(failure)),
    );
    expect(engine.callCountFor('seek'), 1);
    expect(engine.callCountFor('play'), 1);
    expect(handler.playbackState.value.playing, isFalse);

    rejectPlay = false;
    await handler.handlePlay(CommandSource.ui);

    expect(engine.callCountFor('seek'), 2);
    expect(engine.callCountFor('play'), 2);
  });

  test('coalesces two Replay calls into one seek and one Play', () async {
    final item = testPlayerItem(id: 'coalesced-replay-track');
    await _load(handler, engine, [item]);
    await _completeCurrentItem(engine);

    final seekCompleter = Completer<void>();
    engine.seekAction = (_, {index}) => seekCompleter.future;

    final first = handler.handlePlay(CommandSource.ui);
    await pumpEventQueue();
    final second = handler.handlePlay(CommandSource.systemRemote);

    expect(identical(first, second), isTrue);
    expect(engine.callCountFor('seek'), 1);
    expect(engine.callCountFor('play'), 0);

    seekCompleter.complete();
    await Future.wait<void>([first, second]);

    expect(engine.callCountFor('seek'), 1);
    expect(engine.callCountFor('play'), 1);
  });

  test(
    'completed Replay hands the final Play intent through Pause before seek completes',
    () async {
      final item = testPlayerItem(id: 'replay-play-pause-play');
      await _load(handler, engine, [item]);
      await _completeCurrentItem(engine);

      final seekCompleter = Completer<void>();
      engine.seekAction = (_, {index}) => seekCompleter.future;

      final firstPlay = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.callCountFor('seek'), 1);

      final pause = handler.handlePause(CommandSource.ui);
      final finalPlay = handler.handlePlay(CommandSource.systemRemote);

      expect(engine.callCountFor('pause'), 0);

      seekCompleter.complete();
      await Future.wait<void>([firstPlay, pause, finalPlay]);

      expect(engine.callCountFor('seek'), 1);
      expect(engine.callCountFor('play'), 1);
    },
  );

  test(
    'two completed Replay cycles hand off dispatched ownership to the final Play',
    () async {
      final item = testPlayerItem(id: 'replay-two-cycles');
      await _load(handler, engine, [item]);
      await _completeCurrentItem(engine);

      final firstSeek = Completer<void>();
      engine.seekAction = (_, {index}) => firstSeek.future;

      final firstPlay = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.callCountFor('seek'), 1);

      final pause = handler.handlePause(CommandSource.ui);
      final finalPlay = handler.handlePlay(CommandSource.systemRemote);
      expect(engine.callCountFor('pause'), 0);

      firstSeek.complete();
      await Future.wait<void>([firstPlay, pause, finalPlay]);
      expect(engine.callCountFor('play'), 1);

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      await _completeCurrentItem(engine);

      final secondSeek = Completer<void>();
      engine.seekAction = (_, {index}) => secondSeek.future;
      final secondPlay = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.callCountFor('seek'), 2);

      secondSeek.complete();
      await secondPlay;

      expect(engine.callCountFor('seek'), 2);
      expect(engine.callCountFor('play'), 2);
    },
  );

  test('Replay continuation becomes a no-op after handler dispose', () async {
    final item = testPlayerItem(id: 'replay-dispose');
    await _load(handler, engine, [item]);
    await _completeCurrentItem(engine);

    final seek = Completer<void>();
    engine.seekAction = (_, {index}) => seek.future;
    final replay = handler.handlePlay(CommandSource.ui);
    await pumpEventQueue();
    expect(engine.callCountFor('seek'), 1);

    await handler.dispose();
    seek.complete();
    await replay;

    expect(engine.callCountFor('play'), 0);
  });

  test(
    'source replacement invalidates replay after its pending seek',
    () async {
      final itemA = testPlayerItem(id: 'replay-source-a');
      final itemB = testPlayerItem(id: 'replay-source-b');
      final publications = await _listenToPublications(handler);
      await _load(handler, engine, [itemA]);
      await _completeCurrentItem(engine);
      publications.clear();

      final seekCompleter = Completer<void>();
      engine.seekAction = (_, {index}) => seekCompleter.future;
      final replay = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.callCountFor('seek'), 1);

      final loadB = handler.handleLoadQueue(
        [itemB],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(2));

      seekCompleter.complete();
      await replay;
      expect(engine.callCountFor('play'), 0);

      engine.loadRequests.last.complete();
      await loadB;
      await pumpEventQueue();

      expect(handler.mediaItem.value?.id, itemB.id);
      expect(handler.queue.value.map((mediaItem) => mediaItem.id), [itemB.id]);
      expect(publications.snapshots.last.currentItem?.id, itemB.id);
    },
  );
}

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  List<PlayerItem> items, {
  List<int>? effectiveSequence,
}) async {
  final load = handler.handleLoadQueue(items, 0, false, CommandSource.ui);
  await pumpEventQueue();
  if (effectiveSequence != null) {
    engine.emitEffectiveSequence(effectiveSequence);
  }
  engine.loadRequests.last.complete();
  await load;
  await pumpEventQueue();
}

Future<void> _completeCurrentItem(FakePlaybackEngine engine) async {
  engine.emitPlayerState(
    just_audio.PlayerState(false, just_audio.ProcessingState.completed),
  );
  await pumpEventQueue();
}

Future<_Publications> _listenToPublications(AppAudioHandler handler) async {
  final publications = _Publications();
  final snapshotSubscription = handler.snapshots.listen(
    publications.snapshots.add,
  );
  final mediaSubscription = handler.mediaItem.listen(
    publications.mediaItems.add,
  );
  final queueSubscription = handler.queue.listen(
    (items) => publications.queues.add(items.map((item) => item.id).toList()),
  );
  final playbackSubscription = handler.playbackState.listen(
    publications.playbackStates.add,
  );

  await pumpEventQueue();
  publications.clear();

  addTearDown(snapshotSubscription.cancel);
  addTearDown(mediaSubscription.cancel);
  addTearDown(queueSubscription.cancel);
  addTearDown(playbackSubscription.cancel);
  return publications;
}

final class _Publications {
  final List<PlaybackSnapshot> snapshots = <PlaybackSnapshot>[];
  final List<audio_service.MediaItem?> mediaItems =
      <audio_service.MediaItem?>[];
  final List<List<String>> queues = <List<String>>[];
  final List<audio_service.PlaybackState> playbackStates =
      <audio_service.PlaybackState>[];

  void clear() {
    snapshots.clear();
    mediaItems.clear();
    queues.clear();
    playbackStates.clear();
  }
}
