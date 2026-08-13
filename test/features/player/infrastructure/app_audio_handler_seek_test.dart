// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late FakePlayerClock clock;
  late AppAudioHandler handler;
  late List<({String command, CommandSource source})> observedCommands;

  setUp(() {
    engine = FakePlaybackEngine();
    clock = FakePlayerClock();
    observedCommands = <({String command, CommandSource source})>[];
    handler = AppAudioHandler(engine, clock, (command, source) {
      observedCommands.add((command: command, source: source));
    });
  });

  tearDown(() async {
    await handler.dispose();
  });

  test(
    'seek and skipBy reject idle commands without touching the engine',
    () async {
      await expectLater(
        handler.handleSeek(const Duration(seconds: 5), CommandSource.ui),
        _failure('noCurrentItem', 'seek'),
      );
      await expectLater(
        handler.handleSkipBy(const Duration(seconds: 10), CommandSource.ui),
        _failure('noCurrentItem', 'skipBy'),
      );

      expect(engine.calls, isEmpty);
    },
  );

  test('clamps direct seek targets to zero and duration', () async {
    await _load(handler, engine, position: const Duration(seconds: 10));

    await handler.handleSeek(const Duration(seconds: -5), CommandSource.ui);
    await handler.handleSeek(const Duration(seconds: 20), CommandSource.ui);
    await handler.handleSeek(const Duration(seconds: 70), CommandSource.ui);

    expect(
      engine.calls
          .where((call) => call.name == 'seek')
          .map((call) => call.arguments['position']),
      [Duration.zero, const Duration(seconds: 20), const Duration(seconds: 60)],
    );
    expect(engine.calls.where((call) => call.name == 'next'), isEmpty);
    expect(engine.calls.where((call) => call.name == 'previous'), isEmpty);
  });

  test(
    'unknown duration rejects seek and skipBy without engine calls',
    () async {
      await _load(
        handler,
        engine,
        duration: null,
        position: const Duration(seconds: 5),
      );

      await expectLater(
        handler.handleSeek(const Duration(seconds: 5), CommandSource.ui),
        _failure('seekUnavailableUnknownDuration', 'seek'),
      );
      await expectLater(
        handler.handleSkipBy(const Duration(seconds: 10), CommandSource.ui),
        _failure('seekUnavailableUnknownDuration', 'skipBy'),
      );

      expect(engine.callCountFor('seek'), 0);
    },
  );

  test('zero duration rejects seek and skipBy without engine calls', () async {
    await _load(
      handler,
      engine,
      duration: Duration.zero,
      position: const Duration(seconds: 5),
    );

    await expectLater(
      handler.handleSeek(const Duration(seconds: 5), CommandSource.ui),
      _failure('seekUnavailableUnknownDuration', 'seek'),
    );
    await expectLater(
      handler.handleSkipBy(const Duration(seconds: 10), CommandSource.ui),
      _failure('seekUnavailableUnknownDuration', 'skipBy'),
    );

    expect(engine.callCountFor('seek'), 0);
  });

  test(
    'skipBy resolves from the latest reducer position, not UI cadence',
    () async {
      await _load(handler, engine, position: const Duration(seconds: 10));

      engine.emitPosition(const Duration(seconds: 11));
      await pumpEventQueue();

      final gateway = UiPlaybackGatewayAdapter(handler);
      await gateway.skipBy(const Duration(seconds: 10));
      await gateway.skipBy(const Duration(seconds: -10));

      final seekCalls = engine.calls.where((call) => call.name == 'seek');
      expect(seekCalls.map((call) => call.arguments['position']), [
        const Duration(seconds: 21),
        const Duration(seconds: 1),
      ]);
      expect(engine.callCountFor('next'), 0);
      expect(engine.callCountFor('previous'), 0);
    },
  );

  test('UI and OS seek share the operation and preserve provenance', () async {
    await _load(handler, engine, position: const Duration(seconds: 10));
    observedCommands.clear();
    final gateway = UiPlaybackGatewayAdapter(handler);

    await gateway.seek(const Duration(seconds: 20));
    await gateway.skipBy(const Duration(seconds: 10));
    await handler.seek(const Duration(seconds: 30));

    expect(observedCommands, [
      (command: 'seek', source: CommandSource.ui),
      (command: 'skipBy', source: CommandSource.ui),
      (command: 'seek', source: CommandSource.systemRemote),
    ]);
    expect(engine.callCountFor('seek'), 3);
    expect(engine.callCountFor('next'), 0);
    expect(engine.callCountFor('previous'), 0);
  });

  test(
    'seek position event publishes immediately without metadata or queue',
    () async {
      final publications = await _listenToPublications(handler);
      await _load(handler, engine, position: const Duration(seconds: 10));
      publications.clear();

      final seek = handler.handleSeek(
        const Duration(seconds: 20),
        CommandSource.ui,
      );
      await pumpEventQueue();

      expect(publications.snapshots, isEmpty);
      expect(publications.playbackStates, isEmpty);

      engine.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      await seek;

      expect(publications.snapshots, hasLength(1));
      expect(
        publications.snapshots.single.position,
        const Duration(seconds: 20),
      );
      expect(publications.playbackStates, hasLength(1));
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 20),
      );
      expect(publications.mediaItems, isEmpty);
      expect(publications.queues, isEmpty);
    },
  );

  test('stale position tick does not consume seek confirmation', () async {
    final publications = await _listenToPublications(handler);
    await _load(handler, engine, position: const Duration(seconds: 10));
    publications.clear();

    final seek = handler.handleSeek(
      const Duration(seconds: 30),
      CommandSource.ui,
    );
    await pumpEventQueue();

    engine.emitPosition(const Duration(seconds: 11));
    await pumpEventQueue();
    expect(publications.snapshots, isEmpty);

    clock.advance(const Duration(milliseconds: 200));
    await pumpEventQueue();
    expect(publications.snapshots, hasLength(1));
    expect(publications.snapshots.single.position, const Duration(seconds: 11));
    expect(publications.playbackStates, isEmpty);

    engine.emitPosition(const Duration(seconds: 30));
    await pumpEventQueue();
    await seek;

    expect(publications.snapshots, hasLength(2));
    expect(publications.snapshots.last.position, const Duration(seconds: 30));
    expect(publications.playbackStates, hasLength(1));
  });

  test(
    'only the latest seek target bypasses cadence when confirmations reorder',
    () async {
      final publications = await _listenToPublications(handler);
      await _load(handler, engine, position: const Duration(seconds: 10));
      publications.clear();

      final firstSeek = handler.handleSeek(
        const Duration(seconds: 30),
        CommandSource.ui,
      );
      final secondSeek = handler.handleSeek(
        const Duration(seconds: 40),
        CommandSource.ui,
      );
      await pumpEventQueue();

      engine.emitPosition(const Duration(seconds: 40));
      await pumpEventQueue();
      expect(publications.snapshots, hasLength(1));
      expect(
        publications.snapshots.single.position,
        const Duration(seconds: 40),
      );

      engine.emitPosition(const Duration(seconds: 30));
      await pumpEventQueue();
      expect(publications.snapshots, hasLength(1));

      clock.advance(const Duration(milliseconds: 200));
      await pumpEventQueue();
      expect(publications.snapshots, hasLength(2));
      expect(publications.snapshots.last.position, const Duration(seconds: 30));

      await Future.wait<void>([firstSeek, secondSeek]);
    },
  );

  test('rejects seek throughout a pending load window', () async {
    final load = handler.handleLoadQueue(
      [testPlayerItem(id: 'pending-seek')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    await expectLater(
      handler.handleSeek(const Duration(seconds: 5), CommandSource.ui),
      _failure('commandUnavailable', 'seek'),
    );
    expect(engine.callCountFor('seek'), 0);

    engine.loadRequests.single.complete();
    await load;
  });
}

Future<void> _load(
  AppAudioHandler handler,
  FakePlaybackEngine engine, {
  Duration? duration = const Duration(seconds: 60),
  Duration position = Duration.zero,
}) async {
  final load = handler.handleLoadQueue(
    [testPlayerItem(id: 'seek-track')],
    0,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.loadRequests.single.complete();
  if (duration != null) {
    engine.emitDuration(duration);
  }
  engine.emitPosition(position);
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

Matcher _failure(String code, String command) => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.command, 'command', command),
);

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
