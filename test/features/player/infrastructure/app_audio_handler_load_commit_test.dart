// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
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

  test('commits queue and metadata before autoplay is requested', () async {
    final item = testPlayerItem(id: 'autoplay-track');
    var metadataWasCommitted = false;
    engine.playAction = () {
      metadataWasCommitted =
          handler.queue.value
                  .map((mediaItem) => mediaItem.id)
                  .toList()
                  .join() ==
              item.id &&
          handler.mediaItem.value?.id == item.id &&
          handler.playbackState.value.processingState ==
              audio_service.AudioProcessingState.ready &&
          !handler.playbackState.value.playing;
      return Future<void>.value();
    };

    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    final load = handler.handleLoadQueue([item], 0, true, CommandSource.ui);
    await pumpEventQueue();
    engine.loadRequests.single.complete();
    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );

    await load;
    await pumpEventQueue();

    expect(metadataWasCommitted, isTrue);
    expect(engine.calls.map((call) => call.name), ['load', 'play']);
    expect(snapshots.last.processingState, PlaybackProcessingState.ready);
    expect(snapshots.last.playing, isFalse);

    engine.emitPlayerState(
      just_audio.PlayerState(true, just_audio.ProcessingState.ready),
    );
    await pumpEventQueue();

    expect(snapshots.last.processingState, PlaybackProcessingState.ready);
    expect(snapshots.last.playing, isTrue);
  });

  test('commits a successful non-autoplay load as ready and paused', () async {
    final item = testPlayerItem(id: 'paused-track');
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
    await pumpEventQueue();
    expect(snapshots.last.processingState, PlaybackProcessingState.loading);
    expect(snapshots.last.currentItem, isNull);

    engine.loadRequests.single.complete();
    engine.emitDuration(const Duration(minutes: 2));
    await load;
    await pumpEventQueue();

    expect(engine.calls.map((call) => call.name), ['load']);
    expect(snapshots.last, isA<PlaybackSnapshot>());
    expect(snapshots.last.processingState, PlaybackProcessingState.ready);
    expect(snapshots.last.playing, isFalse);
    expect(snapshots.last.currentItem, item);
    expect(snapshots.last.currentIndex, 0);
    expect(snapshots.last.queue, [item]);
    expect(snapshots.last.duration, const Duration(minutes: 2));
    expect(handler.mediaItem.value?.id, item.id);
    expect(handler.queue.value.map((mediaItem) => mediaItem.id), [item.id]);
    expect(
      handler.playbackState.value.processingState,
      audio_service.AudioProcessingState.ready,
    );
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('play failure never leaves the confirmed state playing', () async {
    final item = testPlayerItem(id: 'failed-autoplay-track');
    engine.playAction = () {
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      return Future<void>.error(StateError('play failed'));
    };

    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    final load = handler.handleLoadQueue([item], 0, true, CommandSource.ui);
    await pumpEventQueue();
    engine.loadRequests.single.complete();

    await load;
    await pumpEventQueue();

    expect(engine.calls.map((call) => call.name), ['load', 'play']);
    expect(snapshots.last.playing, isFalse);
    expect(snapshots.last.processingState, PlaybackProcessingState.ready);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      audio_service.AudioProcessingState.ready,
    );
  });

  test(
    'replacement keeps A active until B is ready for atomic commit',
    () async {
      final itemA = testPlayerItem(id: 'track-a');
      final itemB = testPlayerItem(id: 'track-b');
      final snapshots = <PlaybackSnapshot>[];
      final subscription = handler.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final loadA = handler.handleLoadQueue(
        [itemA],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      engine.loadRequests.single.complete();
      await loadA;
      await pumpEventQueue();

      final loadB = handler.handleLoadQueue(
        [itemB],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      expect(snapshots.last.processingState, PlaybackProcessingState.loading);
      expect(snapshots.last.currentItem, itemA);
      expect(snapshots.last.currentIndex, 0);
      expect(snapshots.last.queue, [itemA]);
      expect(handler.mediaItem.value?.id, itemA.id);
      expect(handler.queue.value.map((mediaItem) => mediaItem.id), [itemA.id]);

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      expect(snapshots.last.currentItem, itemA);
      expect(snapshots.last.queue, [itemA]);
      expect(handler.mediaItem.value?.id, itemA.id);

      engine.loadRequests.last.complete();
      engine.emitDuration(const Duration(minutes: 3));
      await loadB;
      await pumpEventQueue();

      expect(snapshots.last.processingState, PlaybackProcessingState.ready);
      expect(snapshots.last.currentItem, itemB);
      expect(snapshots.last.currentIndex, 0);
      expect(snapshots.last.queue, [itemB]);
      expect(snapshots.last.duration, const Duration(minutes: 3));
      expect(handler.mediaItem.value?.id, itemB.id);
      expect(handler.queue.value.map((mediaItem) => mediaItem.id), [itemB.id]);

      for (final snapshot in snapshots) {
        if (snapshot.queue.any((item) => item.id == itemB.id)) {
          expect(snapshot.currentItem?.id, itemB.id);
          expect(snapshot.currentIndex, 0);
          expect(snapshot.processingState, PlaybackProcessingState.ready);
        }
      }
    },
  );

  for (final autoplay in [false, true]) {
    test(
      'replacement from playing A commits B paused before autoplay=$autoplay',
      () async {
        final itemA = testPlayerItem(id: 'playing-track-a');
        final itemB = testPlayerItem(id: 'replacement-track-b');
        final snapshots = <PlaybackSnapshot>[];
        final subscription = handler.snapshots.listen(snapshots.add);
        addTearDown(subscription.cancel);
        await pumpEventQueue();

        final loadA = handler.handleLoadQueue(
          [itemA],
          0,
          false,
          CommandSource.ui,
        );
        await pumpEventQueue();
        engine.loadRequests.single.complete();
        await loadA;
        engine.emitPlayerState(
          just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        );
        await pumpEventQueue();
        expect(snapshots.last.playing, isTrue);

        final loadB = handler.handleLoadQueue(
          [itemB],
          0,
          autoplay,
          CommandSource.ui,
        );
        await pumpEventQueue();
        expect(snapshots.last.currentItem, itemA);
        expect(snapshots.last.playing, isTrue);

        // Model just_audio's retained playing event while the replacement is
        // pending. It must not become B's committed confirmation.
        engine.emitPlayerState(
          just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        );
        engine.loadRequests.last.complete();
        await loadB;
        await pumpEventQueue();

        expect(snapshots.last.currentItem, itemB);
        expect(snapshots.last.processingState, PlaybackProcessingState.ready);
        expect(snapshots.last.playing, isFalse);
        expect(engine.callCountFor('play'), autoplay ? 1 : 0);

        if (autoplay) {
          engine.emitPlayerState(
            just_audio.PlayerState(true, just_audio.ProcessingState.ready),
          );
          await pumpEventQueue();
          expect(snapshots.last.playing, isTrue);
        }
      },
    );
  }

  test('late successful load after dispose is inert', () async {
    final item = testPlayerItem(id: 'disposed-pending-track');
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    final load = handler.handleLoadQueue([item], 0, true, CommandSource.ui);
    await pumpEventQueue();
    final snapshotsBeforeDispose = List<PlaybackSnapshot>.of(snapshots);

    await handler.dispose();
    engine.loadRequests.single.complete();
    await expectLater(load, completes);
    await pumpEventQueue();

    expect(snapshots, snapshotsBeforeDispose);
    expect(handler.queue.value, isEmpty);
    expect(handler.mediaItem.value, isNull);
    expect(engine.calls.map((call) => call.name), ['load']);
  });
}
