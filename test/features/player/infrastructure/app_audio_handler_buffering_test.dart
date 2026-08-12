// SPDX-License-Identifier: Apache-2.0

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

  setUp(() {
    engine = FakePlaybackEngine();
    handler = AppAudioHandler(engine, FakePlayerClock());
  });

  tearDown(() async {
    await handler.dispose();
  });

  test(
    'projects ready playing through buffering recovery without another Play',
    () async {
      final publications = await _loadAndListen(handler, engine);
      final playBaseline = engine.callCountFor('play');
      final pauseBaseline = engine.callCountFor('pause');

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      _expectPublishedState(
        publications,
        processingState: PlaybackProcessingState.ready,
        osProcessingState: audio_service.AudioProcessingState.ready,
        playing: true,
        mainAction: audio_service.MediaAction.pause,
      );

      publications.clear();
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.buffering),
      );
      await pumpEventQueue();
      _expectPublishedState(
        publications,
        processingState: PlaybackProcessingState.buffering,
        osProcessingState: audio_service.AudioProcessingState.buffering,
        playing: true,
        mainAction: audio_service.MediaAction.pause,
      );

      publications.clear();
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      _expectPublishedState(
        publications,
        processingState: PlaybackProcessingState.ready,
        osProcessingState: audio_service.AudioProcessingState.ready,
        playing: true,
        mainAction: audio_service.MediaAction.pause,
      );
      expect(engine.callCountFor('play'), playBaseline);
      expect(engine.callCountFor('pause'), pauseBaseline);
    },
  );

  test(
    'projects buffering paused with Play and no metadata or queue output',
    () async {
      final publications = await _loadAndListen(handler, engine);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.buffering),
      );
      await pumpEventQueue();

      _expectPublishedState(
        publications,
        processingState: PlaybackProcessingState.buffering,
        osProcessingState: audio_service.AudioProcessingState.buffering,
        playing: false,
        mainAction: audio_service.MediaAction.play,
      );
    },
  );

  test(
    'Play during buffering waits for confirmation and does not force ready',
    () async {
      final publications = await _loadAndListen(handler, engine);
      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.buffering),
      );
      await pumpEventQueue();
      publications.clear();
      final playBaseline = engine.callCountFor('play');

      await handler.handlePlay(CommandSource.ui);
      await pumpEventQueue();

      expect(engine.callCountFor('play'), playBaseline + 1);
      expect(publications.snapshots, isEmpty);
      expect(publications.playbackStates, isEmpty);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.buffering,
      );
      expect(handler.playbackState.value.playing, isFalse);

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.buffering),
      );
      await pumpEventQueue();
      _expectPublishedState(
        publications,
        processingState: PlaybackProcessingState.buffering,
        osProcessingState: audio_service.AudioProcessingState.buffering,
        playing: true,
        mainAction: audio_service.MediaAction.pause,
      );
    },
  );

  test(
    'Pause at ready waits for confirmation and keeps ready processing',
    () async {
      final publications = await _loadAndListen(handler, engine);
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      publications.clear();
      final pauseBaseline = engine.callCountFor('pause');

      await handler.handlePause(CommandSource.ui);
      await pumpEventQueue();

      expect(engine.callCountFor('pause'), pauseBaseline + 1);
      expect(publications.snapshots, isEmpty);
      expect(publications.playbackStates, isEmpty);
      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.ready,
      );
      expect(handler.playbackState.value.playing, isTrue);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      _expectPublishedState(
        publications,
        processingState: PlaybackProcessingState.ready,
        osProcessingState: audio_service.AudioProcessingState.ready,
        playing: false,
        mainAction: audio_service.MediaAction.play,
      );
    },
  );

  test('suppresses duplicate buffering player-state publication', () async {
    final publications = await _loadAndListen(handler, engine);
    final buffering = just_audio.PlayerState(
      true,
      just_audio.ProcessingState.buffering,
    );

    engine.emitPlayerState(buffering);
    await pumpEventQueue();
    _expectPublishedState(
      publications,
      processingState: PlaybackProcessingState.buffering,
      osProcessingState: audio_service.AudioProcessingState.buffering,
      playing: true,
      mainAction: audio_service.MediaAction.pause,
    );
    publications.clear();

    engine.emitPlayerState(buffering);
    await pumpEventQueue();

    expect(publications.snapshots, isEmpty);
    expect(publications.playbackStates, isEmpty);
    expect(publications.mediaItems, isEmpty);
    expect(publications.queues, isEmpty);
  });
}

Future<_Publications> _loadAndListen(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
) async {
  final publications = await _listenToPublications(handler);
  final item = testPlayerItem(id: 'buffering-track');
  final load = handler.handleLoadQueue(
    <PlayerItem>[item],
    0,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.loadRequests.last.complete();
  await load;
  await pumpEventQueue();
  publications.clear();
  return publications;
}

void _expectPublishedState(
  _Publications publications, {
  required PlaybackProcessingState processingState,
  required audio_service.AudioProcessingState osProcessingState,
  required bool playing,
  required audio_service.MediaAction mainAction,
}) {
  expect(publications.snapshots, hasLength(1));
  expect(publications.playbackStates, hasLength(1));
  expect(publications.snapshots.single.processingState, processingState);
  expect(publications.snapshots.single.playing, playing);
  expect(publications.playbackStates.single.processingState, osProcessingState);
  expect(publications.playbackStates.single.playing, playing);
  expect(publications.playbackStates.single.controls.first.action, mainAction);
  expect(publications.mediaItems, isEmpty);
  expect(publications.queues, isEmpty);
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
