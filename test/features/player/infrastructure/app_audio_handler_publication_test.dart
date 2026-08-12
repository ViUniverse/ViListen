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
import 'package:vi_listen/features/player/infrastructure/player_clock.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late FakePlayerClock clock;
  late AppAudioHandler handler;

  setUp(() {
    engine = FakePlaybackEngine();
    clock = FakePlayerClock();
    handler = AppAudioHandler(engine, clock);
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('current item change publishes one media item and no queue', () async {
    final itemA = testPlayerItem(id: 'item-a');
    final itemB = testPlayerItem(id: 'item-b');
    final publications = await _listenToPublications(handler);

    await _load(handler, engine, [itemA, itemB]);
    publications.clear();

    engine.emitCurrentIndex(1);
    await pumpEventQueue();

    expect(publications.mediaItems.map((item) => item?.id), ['item-b']);
    expect(publications.queues, isEmpty);
    expect(publications.playbackStates, hasLength(1));
    expect(publications.snapshots.last.currentItem, itemB);
  });

  test('queue change publishes one queue from the domain snapshot', () async {
    final itemA = testPlayerItem(id: 'queue-a');
    final itemB = testPlayerItem(id: 'queue-b');
    final publications = await _listenToPublications(handler);

    await _load(handler, engine, [itemA]);
    publications.clear();

    await _load(handler, engine, [itemA, itemB]);

    expect(publications.queues, [
      <String>['queue-a', 'queue-b'],
    ]);
    expect(publications.mediaItems, isEmpty);
    expect(publications.snapshots.last.currentItem, itemA);
    expect(publications.snapshots.last.queue, [itemA, itemB]);
  });

  test('play, pause and buffering publish playback state only', () async {
    final item = testPlayerItem(id: 'state-track');
    final publications = await _listenToPublications(handler);

    await _load(handler, engine, [item]);
    publications.clear();

    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    engine.emitPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.ready),
    );
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.buffering),
    );
    await pumpEventQueue();

    expect(publications.playbackStates, hasLength(3));
    expect(publications.mediaItems, isEmpty);
    expect(publications.queues, isEmpty);
    expect(
      publications.snapshots.last.processingState,
      PlaybackProcessingState.buffering,
    );
    expect(publications.snapshots.last.playing, isTrue);
  });

  test(
    'position ticks update UI cadence without metadata or queue output',
    () async {
      final item = testPlayerItem(id: 'position-track');
      final publications = await _listenToPublications(handler);

      await _load(handler, engine, [item]);
      publications.clear();

      engine.emitPosition(const Duration(seconds: 1));
      engine.emitPosition(const Duration(seconds: 2));
      engine.emitPosition(const Duration(seconds: 3));
      await pumpEventQueue();

      expect(publications.snapshots, isEmpty);
      expect(publications.playbackStates, isEmpty);

      clock.advance(const Duration(milliseconds: 200));
      await pumpEventQueue();
      expect(publications.snapshots, hasLength(1));
      expect(
        publications.snapshots.single.position,
        const Duration(seconds: 3),
      );
      expect(publications.playbackStates, isEmpty);
      expect(publications.mediaItems, isEmpty);
      expect(publications.queues, isEmpty);

      clock.advance(const Duration(milliseconds: 800));
      await pumpEventQueue();

      expect(publications.playbackStates, hasLength(1));
      expect(
        publications.playbackStates.single.updatePosition,
        const Duration(seconds: 3),
      );
      expect(publications.mediaItems, isEmpty);
      expect(publications.queues, isEmpty);
    },
  );

  test('completed and buffering bypass cadence', () async {
    final item = testPlayerItem(id: 'immediate-track');
    final publications = await _listenToPublications(handler);

    await _load(handler, engine, [item]);
    publications.clear();

    engine.emitPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.buffering),
    );
    await pumpEventQueue();
    expect(
      publications.snapshots.last.processingState,
      PlaybackProcessingState.buffering,
    );

    engine.emitPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.completed),
    );
    await pumpEventQueue();
    expect(
      publications.snapshots.last.processingState,
      PlaybackProcessingState.completed,
    );

    expect(publications.snapshots, hasLength(2));
    expect(publications.playbackStates, hasLength(2));
  });

  test(
    'artwork publication does not participate in playback failure',
    () async {
      final item = testPlayerItem(
        id: 'artwork-track',
        artUri: Uri.parse('https://artwork.invalid/missing.png'),
      );
      final publications = await _listenToPublications(handler);

      await _load(handler, engine, [item]);

      expect(handler.mediaItem.value?.artUri, item.artUri);
      expect(publications.snapshots.last.currentItem, item);
      expect(publications.snapshots.last.failure, isNull);
      expect(
        publications.snapshots.last.processingState,
        PlaybackProcessingState.ready,
      );
    },
  );

  test('handler disposes projectors before its clock exactly once', () async {
    final trackingClock = _TrackingPlayerClock();
    final trackingHandler = AppAudioHandler(
      FakePlaybackEngine(),
      trackingClock,
    );

    await trackingHandler.dispose();
    await trackingHandler.dispose();

    expect(trackingClock.disposeCount, 1);
    expect(trackingClock.hadListenersAtDispose, isFalse);
  });
}

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  List<PlayerItem> items,
) async {
  final load = handler.handleLoadQueue(items, 0, false, CommandSource.ui);
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

final class _TrackingPlayerClock implements PlayerClock {
  final StreamController<Duration> _controller =
      StreamController<Duration>.broadcast(sync: true);

  int disposeCount = 0;
  bool? hadListenersAtDispose;

  @override
  Stream<Duration> get ticks => _controller.stream;

  @override
  Duration get elapsed => Duration.zero;

  @override
  Future<void> dispose() {
    disposeCount += 1;
    hadListenersAtDispose = _controller.hasListener;
    return _controller.close();
  }
}
