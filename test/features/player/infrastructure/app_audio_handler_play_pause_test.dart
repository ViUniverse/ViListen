// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
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

  test(
    'Play at ready dispatches once and waits for engine confirmation',
    () async {
      final item = testPlayerItem(id: 'play-track');
      final publications = await _listenToPublications(handler);
      await _load(handler, engine, [item], autoplay: false);
      publications.clear();

      final playCompletion = Completer<void>();
      engine.playAction = () => playCompletion.future;

      final play = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();

      expect(engine.callCountFor('play'), 1);
      expect(publications.snapshots, isEmpty);
      expect(publications.playbackStates, isEmpty);
      expect(handler.playbackState.value.playing, isFalse);

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      expect(publications.snapshots, hasLength(1));
      expect(publications.snapshots.single.playing, isTrue);
      expect(publications.playbackStates.single.playing, isTrue);

      playCompletion.complete();
      await play;
    },
  );

  test('Pause preserves the queue, current item, and system card', () async {
    final item = testPlayerItem(id: 'pause-track');
    final publications = await _listenToPublications(handler);
    await _load(handler, engine, [item], autoplay: false);
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    await pumpEventQueue();
    publications.clear();

    final pauseCompletion = Completer<void>();
    engine.pauseAction = () => pauseCompletion.future;

    final pause = handler.handlePause(CommandSource.ui);
    await pumpEventQueue();

    expect(engine.callCountFor('pause'), 1);
    expect(publications.snapshots, isEmpty);
    expect(publications.mediaItems, isEmpty);
    expect(publications.queues, isEmpty);
    expect(handler.mediaItem.value?.id, item.id);
    expect(handler.queue.value.map((mediaItem) => mediaItem.id), [item.id]);

    engine.emitPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    await pumpEventQueue();
    expect(publications.snapshots.single.playing, isFalse);

    pauseCompletion.complete();
    await pause;
  });

  test(
    'idle Pause is a successful no-op and idle Play is noCurrentItem',
    () async {
      await expectLater(handler.pause(), completes);
      await expectLater(
        handler.play(),
        throwsA(
          isA<PlayerCommandFailure>()
              .having((failure) => failure.code, 'code', 'noCurrentItem')
              .having((failure) => failure.command, 'command', 'play'),
        ),
      );
      expect(engine.calls, isEmpty);
    },
  );

  test('coalesces rapid Play/Play and Pause/Pause', () async {
    final item = testPlayerItem(id: 'coalesce-track');
    await _load(handler, engine, [item], autoplay: false);

    final playCompletion = Completer<void>();
    engine.playAction = () => playCompletion.future;
    final firstPlay = handler.handlePlay(CommandSource.ui);
    await pumpEventQueue();
    final secondPlay = handler.handlePlay(CommandSource.systemRemote);

    expect(identical(firstPlay, secondPlay), isTrue);
    expect(engine.callCountFor('play'), 1);
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    playCompletion.complete();
    await Future.wait<void>([firstPlay, secondPlay]);

    final pauseCompletion = Completer<void>();
    engine.pauseAction = () => pauseCompletion.future;
    final firstPause = handler.handlePause(CommandSource.ui);
    await pumpEventQueue();
    final secondPause = handler.handlePause(CommandSource.systemRemote);

    expect(identical(firstPause, secondPause), isTrue);
    expect(engine.callCountFor('pause'), 1);
    engine.emitPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    pauseCompletion.complete();
    await Future.wait<void>([firstPause, secondPause]);
  });

  test(
    'Play Future completion before confirmation still dispatches Pause',
    () async {
      final item = testPlayerItem(id: 'early-play-completion');
      await _load(handler, engine, [item], autoplay: false);

      engine.playAction = () => Future<void>.value();
      final play = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      await play;

      final pause = handler.handlePause(CommandSource.ui);
      await pumpEventQueue();

      expect(engine.callCountFor('play'), 1);
      expect(engine.callCountFor('pause'), 1);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      await pause;
    },
  );

  test(
    'Pause Future completion before confirmation coalesces the second Pause',
    () async {
      final item = testPlayerItem(id: 'early-pause-completion');
      await _load(handler, engine, [item], autoplay: false);
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      engine.pauseAction = () => Future<void>.value();
      final firstPause = handler.handlePause(CommandSource.ui);
      await pumpEventQueue();
      await firstPause;

      final secondPause = handler.handlePause(CommandSource.systemRemote);

      expect(identical(firstPause, secondPause), isTrue);
      expect(engine.callCountFor('pause'), 1);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      await secondPause;
    },
  );

  test(
    'Play then Pause dispatches Pause while Play Future is pending',
    () async {
      final item = testPlayerItem(id: 'lifetime-play-track');
      await _load(handler, engine, [item], autoplay: false);

      final playCompletion = Completer<void>();
      final pauseCompletion = Completer<void>();
      engine.playAction = () => playCompletion.future;
      engine.pauseAction = () {
        if (!playCompletion.isCompleted) {
          playCompletion.complete();
        }
        return pauseCompletion.future;
      };

      final play = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      final pause = handler.handlePause(CommandSource.ui);
      await pumpEventQueue();

      expect(engine.calls.skip(1).map((call) => call.name), ['play', 'pause']);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      pauseCompletion.complete();
      await Future.wait<void>([play, pause]);
    },
  );

  test('Pause then Play dispatches Play after the pending Pause', () async {
    final item = testPlayerItem(id: 'lifetime-pause-track');
    await _load(handler, engine, [item], autoplay: false);
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    await pumpEventQueue();

    final pauseCompletion = Completer<void>();
    final playCompletion = Completer<void>();
    engine.pauseAction = () => pauseCompletion.future;
    engine.playAction = () => playCompletion.future;

    final pause = handler.handlePause(CommandSource.ui);
    await pumpEventQueue();
    final play = handler.handlePlay(CommandSource.ui);
    await pumpEventQueue();

    expect(engine.calls.skip(1).map((call) => call.name), ['pause', 'play']);

    pauseCompletion.complete();
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    playCompletion.complete();
    await Future.wait<void>([pause, play]);
  });

  test('loading Pause overrides autoplay and does not call Play', () async {
    final item = testPlayerItem(id: 'loading-autoplay-pause');
    final load = handler.handleLoadQueue([item], 0, true, CommandSource.ui);
    await pumpEventQueue();

    await handler.handlePause(CommandSource.ui);
    expect(engine.callCountFor('play'), 0);
    expect(engine.callCountFor('pause'), 0);

    engine.loadRequests.single.complete();
    await load;
    await pumpEventQueue();

    expect(engine.calls.map((call) => call.name), ['load']);
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.mediaItem.value?.id, item.id);
  });

  test(
    'loading Play overrides autoplay=false and plays after commit',
    () async {
      final item = testPlayerItem(id: 'loading-explicit-play');
      final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
      await pumpEventQueue();

      await handler.handlePlay(CommandSource.ui);
      expect(engine.callCountFor('play'), 0);

      engine.loadRequests.single.complete();
      await load;
      await pumpEventQueue();

      expect(engine.callCountFor('play'), 1);
      expect(handler.playbackState.value.playing, isFalse);
    },
  );

  test('loading rapid intent uses the final desired value', () async {
    final itemA = testPlayerItem(id: 'loading-last-pause');
    final loadA = handler.handleLoadQueue([itemA], 0, false, CommandSource.ui);
    await pumpEventQueue();
    await handler.handlePlay(CommandSource.ui);
    await handler.handlePause(CommandSource.ui);
    engine.loadRequests.single.complete();
    await loadA;
    await pumpEventQueue();
    expect(engine.callCountFor('play'), 0);

    final itemB = testPlayerItem(id: 'loading-last-play');
    final loadB = handler.handleLoadQueue([itemB], 0, true, CommandSource.ui);
    await pumpEventQueue();
    await handler.handlePause(CommandSource.ui);
    await handler.handlePlay(CommandSource.ui);
    engine.loadRequests.last.complete();
    await loadB;
    await pumpEventQueue();
    expect(engine.callCountFor('play'), 1);
  });

  test(
    'stale confirmation and error do not clear the newer Pause intent',
    () async {
      final item = testPlayerItem(id: 'stale-intent-track');
      await _load(handler, engine, [item], autoplay: false);

      final playCompletion = Completer<void>();
      final pauseCompletion = Completer<void>();
      engine.playAction = () => playCompletion.future;
      engine.pauseAction = () => pauseCompletion.future;

      final play = handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();
      final pause = handler.handlePause(CommandSource.ui);
      await pumpEventQueue();
      expect(engine.callCountFor('pause'), 1);

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      final playFailure = StateError('old play rejected');
      playCompletion.completeError(playFailure);
      await expectLater(play, throwsA(same(playFailure)));

      // A stale Play confirmation/error must not cause a second Pause call.
      final secondPause = handler.handlePause(CommandSource.ui);
      expect(identical(pause, secondPause), isTrue);
      expect(engine.callCountFor('pause'), 1);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      pauseCompletion.complete();
      await Future.wait<void>([pause, secondPause]);
    },
  );
}

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  List<PlayerItem> items, {
  required bool autoplay,
}) async {
  final load = handler.handleLoadQueue(items, 0, autoplay, CommandSource.ui);
  await pumpEventQueue();
  engine.loadRequests.last.complete();
  await load;
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
