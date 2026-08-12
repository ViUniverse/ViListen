// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/player_failure_mapper.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late AppAudioHandler handler;
  late List<PlaybackSnapshot> snapshots;
  late StreamSubscription<PlaybackSnapshot> snapshotSubscription;

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
    snapshots = <PlaybackSnapshot>[];
    snapshotSubscription = handler.snapshots.listen(snapshots.add);
  });

  tearDown(() async {
    await snapshotSubscription.cancel();
    await handler.dispose();
  });

  test(
    'normalizes every supported runtime category through the handler',
    () async {
      final item = testPlayerItem(id: 'runtime-category');
      await _load(handler, engine, item);

      final cases =
          <({int engineCode, String signal, String code, bool recoverable})>[
            (
              engineCode: 0,
              signal: 'Network unavailable',
              code: 'network',
              recoverable: true,
            ),
            (
              engineCode: 0,
              signal: 'Audio source not found',
              code: 'not_found',
              recoverable: false,
            ),
            (
              engineCode: 0,
              signal: 'Unsupported audio format',
              code: 'unsupported_format',
              recoverable: false,
            ),
            (
              engineCode: 0,
              signal: 'Audio output device unavailable',
              code: 'audio_output',
              recoverable: true,
            ),
            (
              engineCode: 9999,
              signal: 'unclassified failure',
              code: 'unknown_engine',
              recoverable: false,
            ),
          ];

      for (final value in cases) {
        engine.emitError(
          just_audio.PlayerException(value.engineCode, value.signal, 0),
        );
        await pumpEventQueue();

        final failure = handler.playbackState.value;
        expect(
          failure.processingState,
          audio_service.AudioProcessingState.error,
        );
        expect(failure.playing, isFalse);
        expect(snapshots.last.failure?.code, value.code);
        expect(snapshots.last.failure?.isRecoverable, value.recoverable);
      }
    },
  );

  test(
    'initial load failure stays empty and rethrows the original error',
    () async {
      final item = testPlayerItem(id: 'initial-failure');
      final load = handler.handleLoadQueue([item], 0, true, CommandSource.ui);
      await pumpEventQueue();
      final error = just_audio.PlayerException(0, 'Network unavailable', 0);

      engine.loadRequests.single.completeError(error);

      await expectLater(load, throwsA(same(error)));
      await pumpEventQueue();

      final snapshot = snapshots.last;
      expect(snapshot.processingState, PlaybackProcessingState.error);
      expect(snapshot.playing, isFalse);
      expect(snapshot.currentItem, isNull);
      expect(snapshot.currentIndex, isNull);
      expect(snapshot.queue, isEmpty);
      expect(snapshot.failure?.itemId, item.id);
      expect(handler.retryContext?.restorePosition, Duration.zero);
      expect(handler.mediaItem.value, isNull);
      expect(handler.queue.value, isEmpty);
      expect(handler.playbackState.value.errorCode, 1001);
      expect(handler.playbackState.value.errorMessage, 'Network unavailable.');
    },
  );

  test('replace failure retains A but identifies failed target B', () async {
    final itemA = testPlayerItem(id: 'active-a');
    final itemB = testPlayerItem(id: 'pending-b');
    await _load(handler, engine, itemA);
    engine.emitPosition(const Duration(seconds: 12));
    await pumpEventQueue();

    final loadB = handler.handleLoadQueue([itemB], 0, true, CommandSource.ui);
    await pumpEventQueue();
    final error = just_audio.PlayerException(0, 'Network unavailable', 0);
    engine.loadRequests.last.completeError(error);

    await expectLater(loadB, throwsA(same(error)));
    await pumpEventQueue();

    final snapshot = snapshots.last;
    expect(snapshot.processingState, PlaybackProcessingState.error);
    expect(snapshot.playing, isFalse);
    expect(snapshot.currentItem, itemA);
    expect(snapshot.currentIndex, 0);
    expect(snapshot.queue, [itemA]);
    expect(snapshot.position, const Duration(seconds: 12));
    expect(snapshot.failure?.itemId, itemB.id);
    expect(handler.retryContext?.restorePosition, Duration.zero);
    expect(handler.mediaItem.value?.id, itemA.id);
    expect(handler.queue.value.map((mediaItem) => mediaItem.id), [itemA.id]);
  });

  test(
    'runtime error retains active context and cannot be resurrected playing',
    () async {
      final item = testPlayerItem(id: 'runtime-item');
      await _load(handler, engine, item);
      engine.emitDuration(const Duration(minutes: 2));
      engine.emitPosition(const Duration(seconds: 37));
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      engine.emitError(
        just_audio.PlayerException(
          0,
          'Network unavailable token=secret-url',
          0,
        ),
      );
      await pumpEventQueue();

      expect(snapshots.last.currentItem, item);
      expect(snapshots.last.queue, [item]);
      expect(snapshots.last.position, const Duration(seconds: 37));
      expect(snapshots.last.duration, const Duration(minutes: 2));
      expect(snapshots.last.processingState, PlaybackProcessingState.error);
      expect(snapshots.last.playing, isFalse);
      expect(
        handler.retryContext?.restorePosition,
        const Duration(seconds: 37),
      );
      expect(handler.playbackState.value.errorCode, 1001);
      expect(handler.playbackState.value.errorMessage, 'Network unavailable.');
      expect(
        handler.playbackState.value.errorMessage,
        isNot(contains('secret')),
      );

      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      expect(snapshots.last.processingState, PlaybackProcessingState.error);
      expect(snapshots.last.playing, isFalse);
    },
  );

  test(
    'runtime retry context keeps an unprojected position candidate',
    () async {
      final item = testPlayerItem(id: 'unprojected-position');
      await _load(handler, engine, item);

      engine.emitPosition(const Duration(seconds: 37));
      engine.emitError(just_audio.PlayerException(0, 'Network unavailable', 0));
      await pumpEventQueue();

      expect(snapshots.last.processingState, PlaybackProcessingState.error);
      expect(snapshots.last.position, const Duration(seconds: 37));
      expect(
        handler.retryContext?.restorePosition,
        const Duration(seconds: 37),
      );
    },
  );

  test('untagged error stream is ignored while a load is pending', () async {
    final item = testPlayerItem(id: 'pending-error');
    final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
    await pumpEventQueue();

    engine.emitError(just_audio.PlayerException(0, 'Network unavailable', 0));
    await pumpEventQueue();
    expect(snapshots.last.processingState, PlaybackProcessingState.loading);
    expect(snapshots.last.failure, isNull);

    engine.loadRequests.single.complete();
    await load;
  });

  test('late stale load Future error after B commits is ignored', () async {
    final lateEngine = FakePlaybackEngine(interruptCompletesLoad: false);
    final lateHandler = AppAudioHandler(
      lateEngine,
      FakePlayerClock(),
      null,
      null,
      null,
      () => PlayerFailurePlatform.android,
    );
    final lateSnapshots = <PlaybackSnapshot>[];
    final lateSubscription = lateHandler.snapshots.listen(lateSnapshots.add);
    addTearDown(lateSubscription.cancel);
    addTearDown(lateHandler.dispose);
    await pumpEventQueue();

    final itemA = testPlayerItem(id: 'stale-a');
    final itemB = testPlayerItem(id: 'current-b');
    final loadA = lateHandler.handleLoadQueue(
      [itemA],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    final requestA = lateEngine.loadRequests.single;
    final loadB = lateHandler.handleLoadQueue(
      [itemB],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    await loadA;
    lateEngine.loadRequests.last.complete();
    await loadB;
    await pumpEventQueue();

    requestA.completeError(
      just_audio.PlayerException(0, 'Network unavailable', 0),
    );
    await pumpEventQueue();

    expect(lateSnapshots.last.currentItem, itemB);
    expect(lateSnapshots.last.failure, isNull);
    expect(
      lateHandler.playbackState.value.processingState,
      audio_service.AudioProcessingState.ready,
    );
    expect(lateHandler.playbackState.value.errorCode, isNull);
  });

  test(
    'non-recoverable failure leaves retry unavailable without engine work',
    () async {
      final item = testPlayerItem(id: 'unsupported');
      await _load(handler, engine, item);
      engine.emitError(just_audio.PlayerException(0, 'Unsupported format', 0));
      await pumpEventQueue();
      final callsBeforeRetry = engine.calls.length;

      await expectLater(
        handler.handleRetry(CommandSource.ui),
        throwsA(
          isA<PlayerCommandFailure>().having(
            (failure) => failure.code,
            'code',
            'commandUnavailable',
          ),
        ),
      );
      expect(engine.calls, hasLength(callsBeforeRetry));
    },
  );
}

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine,
  PlayerItem item,
) async {
  final load = handler.handleLoadQueue([item], 0, false, CommandSource.ui);
  await pumpEventQueue();
  engine.loadRequests.single.complete();
  await load;
  await pumpEventQueue();
}
