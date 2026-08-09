// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
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

  test('rejects invalid input before engine or snapshot publication', () async {
    final snapshots = <PlaybackSnapshot>[];
    final subscription = handler.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await expectLater(
      handler.handleLoadQueue(const [], 0, true, CommandSource.ui),
      _loadFailure('emptyQueue'),
    );
    await pumpEventQueue();

    expect(engine.calls, isEmpty);
    expect(snapshots, [PlaybackSnapshot.idle]);
    expect(handler.mediaItem.value, isNull);
    expect(handler.queue.value, isEmpty);
  });

  test(
    'emits loading before exposing a pending target to current state',
    () async {
      final snapshots = <PlaybackSnapshot>[];
      final subscription = handler.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final item = testPlayerItem(id: 'pending-track');
      final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
      await pumpEventQueue();

      expect(snapshots.last.processingState, PlaybackProcessingState.loading);
      expect(snapshots.last.currentItem, isNull);
      expect(snapshots.last.currentIndex, isNull);
      expect(snapshots.last.queue, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(engine.loadRequests, hasLength(1));

      final source = engine.loadRequests.single.sources.single;
      expect(source, isA<just_audio.UriAudioSource>());
      final tag = (source as just_audio.UriAudioSource).tag;
      expect(tag, isA<audio_service.MediaItem>());
      expect((tag! as audio_service.MediaItem).id, item.id);

      engine.loadRequests.single.complete();
      await load;
      expect(snapshots.last.processingState, PlaybackProcessingState.loading);
      expect(snapshots.last.queue, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
    },
  );

  test(
    'buffers every pending engine event outside the outward snapshot',
    () async {
      final snapshots = <PlaybackSnapshot>[];
      final subscription = handler.snapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      final load = handler.handleLoadQueue(
        [testPlayerItem(id: 'pending-track')],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      final beforeEngineEvents = List<PlaybackSnapshot>.of(snapshots);
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      engine.emitPosition(const Duration(seconds: 11));
      engine.emitBufferedPosition(const Duration(seconds: 13));
      engine.emitDuration(const Duration(minutes: 2));
      engine.emitCurrentIndex(0);
      engine.emitSpeed(1.5);
      engine.emitLoopMode(just_audio.LoopMode.all);
      engine.emitShuffleModeEnabled(true);
      await pumpEventQueue();

      expect(snapshots, beforeEngineEvents);

      engine.loadRequests.single.complete();
      await load;
    },
  );

  test(
    'interrupts a pending load before starting a newer valid load',
    () async {
      final firstLoad = handler.handleLoadQueue(
        [testPlayerItem(id: 'first-track')],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();
      expect(engine.loadRequests, hasLength(1));

      final secondLoad = handler.handleLoadQueue(
        [testPlayerItem(id: 'second-track')],
        0,
        false,
        CommandSource.ui,
      );
      await pumpEventQueue();

      expect(engine.calls.map((call) => call.name), [
        'load',
        'interruptLoad',
        'load',
      ]);
      expect(engine.loadRequests, hasLength(2));

      // The stale first result is absorbed after its generation is invalidated;
      // the latest request remains independently controllable.
      engine.loadRequests.last.complete();
      await firstLoad;
      await secondLoad;
    },
  );
}

Matcher _loadFailure(String code) => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.command, 'command', 'loadQueue'),
);
