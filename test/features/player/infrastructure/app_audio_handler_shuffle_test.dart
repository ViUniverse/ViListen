// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_call_recorder.dart';
import '../support/player_test_data.dart';

void main() {
  late _ShuffleTestEngine engine;
  late AppAudioHandler handler;

  setUp(() {
    engine = _ShuffleTestEngine(FakePlaybackEngine());
    handler = AppAudioHandler(engine, FakePlayerClock());
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('rejects shuffle without a current item', () async {
    await expectLater(
      handler.handleSetShuffleEnabled(true, CommandSource.ui),
      throwsA(
        isA<PlayerCommandFailure>().having(
          (failure) => failure.code,
          'code',
          'noCurrentItem',
        ),
      ),
    );
    expect(engine.shuffleCalls, isEmpty);
  });

  test(
    'joins mode and sequence when mode confirmation arrives first',
    () async {
      final items = _items(3);
      final publications = await _listenToPublications(handler);
      await _loadReady(handler, engine, items);
      publications.clear();

      final operation = handler.handleSetShuffleEnabled(true, CommandSource.ui);
      await pumpEventQueue();

      expect(engine.shuffleCalls, [true]);
      expect(publications.snapshots, isEmpty);

      engine.emitShuffleModeEnabled(true);
      await pumpEventQueue();
      expect(publications.snapshots, isEmpty);

      engine.emitEffectiveSequence([2, 0, 1]);
      await operation;
      await pumpEventQueue();

      _expectShuffled(publications, items);
    },
  );

  test(
    'joins sequence and mode when sequence confirmation arrives first',
    () async {
      final items = _items(3);
      final publications = await _listenToPublications(handler);
      await _loadReady(handler, engine, items);
      publications.clear();

      final operation = handler.handleSetShuffleEnabled(true, CommandSource.ui);
      await pumpEventQueue();

      engine.emitEffectiveSequence([2, 0, 1]);
      await pumpEventQueue();
      expect(publications.snapshots, isEmpty);

      engine.emitShuffleModeEnabled(true);
      await operation;
      await pumpEventQueue();

      _expectShuffled(publications, items);
    },
  );

  test(
    'publishes one atomic queue update and keeps the current item',
    () async {
      final items = _items(3);
      final publications = await _listenToPublications(handler);
      await _loadReady(handler, engine, items, initialIndex: 0);
      publications.clear();

      final operation = handler.handleSetShuffleEnabled(true, CommandSource.ui);
      engine.emitShuffleModeEnabled(true);
      engine.emitEffectiveSequence([2, 0, 1]);
      await operation;
      await pumpEventQueue();

      expect(publications.snapshots, hasLength(1));
      expect(publications.snapshots.single.shuffleEnabled, isTrue);
      expect(publications.snapshots.single.queue, [
        items[2],
        items[0],
        items[1],
      ]);
      expect(publications.snapshots.single.currentItem, items[0]);
      expect(publications.snapshots.single.currentIndex, 1);
      expect(publications.queues, [
        <String>['track-2', 'track-0', 'track-1'],
      ]);
      expect(publications.mediaItems, isEmpty);
      expect(publications.playbackStates, hasLength(1));
      expect(publications.playbackStates.single.queueIndex, 1);
      expect(
        publications.playbackStates.single.shuffleMode,
        audio_service.AudioServiceShuffleMode.all,
      );
      expect(engine.calls.map((call) => call.name), [
        'load',
        'setShuffleEnabled',
      ]);
    },
  );

  test('disable accepts only the identity sequence', () async {
    final items = _items(3);
    final publications = await _listenToPublications(handler);
    await _loadReady(handler, engine, items);
    await _toggleShuffle(handler, engine, true, [2, 0, 1]);
    publications.clear();

    final operation = handler.handleSetShuffleEnabled(false, CommandSource.ui);
    engine.emitShuffleModeEnabled(false);
    engine.emitEffectiveSequence([2, 0, 1]);
    await pumpEventQueue();
    expect(publications.snapshots, isEmpty);

    engine.emitEffectiveSequence([0, 1, 2]);
    await operation;
    await pumpEventQueue();

    expect(publications.snapshots, hasLength(1));
    expect(publications.snapshots.single.shuffleEnabled, isFalse);
    expect(publications.snapshots.single.queue, items);
    expect(publications.snapshots.single.currentItem, items[0]);
    expect(publications.snapshots.single.currentIndex, 0);
    expect(publications.queues, [
      <String>['track-0', 'track-1', 'track-2'],
    ]);
    expect(publications.playbackStates.single.queueIndex, 0);
    expect(engine.shuffleCalls, [true, false]);
  });

  test('invalid sequence does not commit the shuffle flight', () async {
    final items = _items(3);
    final publications = await _listenToPublications(handler);
    await _loadReady(handler, engine, items);
    publications.clear();

    final operation = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([0, 0, 1]);
    await pumpEventQueue();
    expect(publications.snapshots, isEmpty);

    engine.emitEffectiveSequence([1, 2, 0]);
    await operation;
    await pumpEventQueue();

    expect(publications.snapshots.single.queue, [items[1], items[2], items[0]]);
    expect(publications.snapshots.single.currentItem, items[0]);
    expect(publications.snapshots.single.currentIndex, 2);
  });

  test('identical requests share one engine call', () async {
    final items = _items(2);
    await _loadReady(handler, engine, items);
    final platformCall = Completer<void>();
    engine.shuffleAction = (_) => platformCall.future;

    final first = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    final second = handler.handleSetShuffleEnabled(true, CommandSource.ui);

    expect(identical(first, second), isTrue);
    expect(engine.shuffleCalls, [true]);

    platformCall.complete();
    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([1, 0]);
    await Future.wait<void>([first, second]);
  });

  test('keeps the latest ready A-B-A intent', () async {
    final items = _items(2);
    await _loadReady(handler, engine, items);
    final firstPlatformCall = Completer<void>();
    var callNumber = 0;
    engine.shuffleAction = (_) {
      callNumber += 1;
      return callNumber == 1 ? firstPlatformCall.future : Future<void>.value();
    };

    final first = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    final middle = handler.handleSetShuffleEnabled(false, CommandSource.ui);
    final last = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    expect(engine.shuffleCalls, [true]);

    firstPlatformCall.complete();
    await first;
    await pumpEventQueue();
    expect(engine.shuffleCalls, [true, true]);

    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([1, 0]);
    await Future.wait<void>([first, middle, last]);
    await pumpEventQueue();

    expect(
      handler.playbackState.value.shuffleMode,
      audio_service.AudioServiceShuffleMode.all,
    );
    expect(handler.queue.value.map((item) => item.id), ['track-1', 'track-0']);
  });

  test(
    'does not republish duplicate mode and sequence confirmations',
    () async {
      final items = _items(2);
      final publications = await _listenToPublications(handler);
      await _loadReady(handler, engine, items);
      publications.clear();

      await _toggleShuffle(handler, engine, true, [1, 0]);
      final snapshotCount = publications.snapshots.length;
      final queueCount = publications.queues.length;
      final playbackStateCount = publications.playbackStates.length;

      engine.emitShuffleModeEnabled(true);
      engine.emitEffectiveSequence([1, 0]);
      await pumpEventQueue();

      expect(publications.snapshots, hasLength(snapshotCount));
      expect(publications.queues, hasLength(queueCount));
      expect(publications.playbackStates, hasLength(playbackStateCount));
    },
  );

  test('keeps the latest pending-load A-B-A intent', () async {
    final items = _items(2);
    final load = handler.handleLoadQueue(items, 0, false, CommandSource.ui);
    await pumpEventQueue();

    final firstPlatformCall = Completer<void>();
    var callNumber = 0;
    engine.shuffleAction = (_) {
      callNumber += 1;
      return callNumber == 1 ? firstPlatformCall.future : Future<void>.value();
    };

    final first = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    final middle = handler.handleSetShuffleEnabled(false, CommandSource.ui);
    final last = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    expect(engine.shuffleCalls, [true]);

    firstPlatformCall.complete();
    await first;
    await pumpEventQueue();
    expect(engine.shuffleCalls, [true, true]);

    engine.loadRequests.single.complete();
    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([1, 0]);
    await Future.wait<void>([load, first, middle, last]);
    await pumpEventQueue();

    expect(handler.queue.value.map((item) => item.id), ['track-1', 'track-0']);
    expect(
      handler.playbackState.value.shuffleMode,
      audio_service.AudioServiceShuffleMode.all,
    );
  });

  test(
    'does not use a pre-command pending sequence as shuffle confirmation',
    () async {
      final items = _items(2);
      final publications = await _listenToPublications(handler);
      final load = handler.handleLoadQueue(items, 0, false, CommandSource.ui);
      await pumpEventQueue();

      // This identity sequence belongs to the pending load, not to the
      // shuffle command that is dispatched below.
      engine.emitEffectiveSequence([0, 1]);
      await pumpEventQueue();
      publications.clear();

      final shuffle = handler.handleSetShuffleEnabled(true, CommandSource.ui);
      await pumpEventQueue();
      expect(engine.shuffleCalls, [true]);

      engine.loadRequests.single.complete();
      engine.emitShuffleModeEnabled(true);
      await pumpEventQueue();

      // Mode confirmation alone must not let the load commit with the stale
      // identity sequence.
      expect(publications.snapshots, isEmpty);
      expect(handler.queue.value, isEmpty);

      engine.emitEffectiveSequence([1, 0]);
      await Future.wait<void>([load, shuffle]);
      await pumpEventQueue();

      expect(publications.snapshots, hasLength(1));
      expect(publications.snapshots.single.queue, [items[1], items[0]]);
      expect(publications.snapshots.single.currentItem, items[0]);
      expect(publications.snapshots.single.currentIndex, 1);
      expect(publications.queues, [
        <String>['track-1', 'track-0'],
      ]);
      expect(publications.mediaItems, hasLength(1));
      expect(publications.mediaItems.single?.id, 'track-0');
      expect(publications.playbackStates.single.queueIndex, 1);
    },
  );

  test('reapplies desired shuffle for a new load generation', () async {
    final items = _items(2);
    await _loadReady(handler, engine, items);
    await _toggleShuffle(handler, engine, true, [1, 0]);

    final nextItem = testPlayerItem(id: 'next-track');
    final load = handler.handleLoadQueue(
      [nextItem, items[1]],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    engine.loadRequests.last.complete();
    await pumpEventQueue();

    expect(engine.shuffleCalls, [true, true]);
    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([1, 0]);
    await load;
    await pumpEventQueue();

    expect(
      handler.playbackState.value.shuffleMode,
      audio_service.AudioServiceShuffleMode.all,
    );
    expect(handler.queue.value.map((item) => item.id), [
      'track-1',
      'next-track',
    ]);
    expect(handler.playbackState.value.queueIndex, 1);
  });

  test('a replacement invalidates a pending shuffle candidate', () async {
    final items = _items(2);
    await _loadReady(handler, engine, items);
    await _toggleShuffle(handler, engine, true, [1, 0]);

    final loadC = handler.handleLoadQueue(
      [testPlayerItem(id: 'load-c')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    engine.loadRequests.last.complete();
    await pumpEventQueue();
    expect(engine.shuffleCalls, [true, true]);

    final loadD = handler.handleLoadQueue(
      [testPlayerItem(id: 'load-d'), testPlayerItem(id: 'load-d-2')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    engine.loadRequests.last.complete();
    await pumpEventQueue();

    expect(engine.shuffleCalls, [true, true, true]);
    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([1, 0]);
    await Future.wait<void>([loadC, loadD]);
    await pumpEventQueue();

    expect(handler.queue.value.map((item) => item.id), ['load-d-2', 'load-d']);
    expect(handler.mediaItem.value?.id, 'load-d');
  });

  test('engine failure releases the shuffle flight', () async {
    final items = _items(2);
    await _loadReady(handler, engine, items);
    engine.shuffleAction = (_) =>
        Future<void>.error(StateError('shuffle failed'));

    await expectLater(
      handler.handleSetShuffleEnabled(true, CommandSource.ui),
      throwsA(isA<StateError>()),
    );
    expect(
      handler.playbackState.value.shuffleMode,
      audio_service.AudioServiceShuffleMode.none,
    );

    engine.shuffleAction = (_) => Future<void>.value();
    final operation = handler.handleSetShuffleEnabled(true, CommandSource.ui);
    engine.emitShuffleModeEnabled(true);
    engine.emitEffectiveSequence([1, 0]);
    await operation;
    await pumpEventQueue();
    expect(
      handler.playbackState.value.shuffleMode,
      audio_service.AudioServiceShuffleMode.all,
    );
  });
}

void _expectShuffled(_Publications publications, List<PlayerItem> items) {
  expect(publications.snapshots, hasLength(1));
  expect(publications.snapshots.single.shuffleEnabled, isTrue);
  expect(publications.snapshots.single.queue, [items[2], items[0], items[1]]);
  expect(publications.snapshots.single.currentItem, items[0]);
  expect(publications.snapshots.single.currentIndex, 1);
  expect(publications.queues, [
    <String>['track-2', 'track-0', 'track-1'],
  ]);
  expect(publications.mediaItems, isEmpty);
  expect(publications.playbackStates, hasLength(1));
  expect(publications.playbackStates.single.queueIndex, 1);
}

Future<void> _toggleShuffle(
  AppAudioHandler handler,
  _ShuffleTestEngine engine,
  bool enabled,
  List<int> sequence,
) async {
  final operation = handler.handleSetShuffleEnabled(enabled, CommandSource.ui);
  engine.emitShuffleModeEnabled(enabled);
  engine.emitEffectiveSequence(sequence);
  await operation;
  await pumpEventQueue();
}

Future<void> _loadReady(
  AppAudioHandler handler,
  _ShuffleTestEngine engine,
  List<PlayerItem> items, {
  int initialIndex = 0,
  List<int>? effectiveSequence,
}) async {
  final load = handler.handleLoadQueue(
    items,
    initialIndex,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.loadRequests.last.complete();
  if (effectiveSequence != null) {
    engine.emitEffectiveSequence(effectiveSequence);
  }
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

List<PlayerItem> _items(int count) => List<PlayerItem>.generate(
  count,
  (index) => testPlayerItem(id: 'track-$index'),
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

final class _ShuffleTestEngine implements PlaybackEngine {
  _ShuffleTestEngine(this.delegate);

  final FakePlaybackEngine delegate;
  Future<void> Function(bool enabled)? shuffleAction;

  List<FakeLoadRequest> get loadRequests => delegate.loadRequests;

  List<RecordedPlayerCall> get calls => delegate.calls;

  List<bool> get shuffleCalls => calls
      .where((call) => call.name == 'setShuffleEnabled')
      .map((call) => call.arguments['enabled']! as bool)
      .toList(growable: false);

  void emitShuffleModeEnabled(bool enabled) =>
      delegate.emitShuffleModeEnabled(enabled);

  void emitEffectiveSequence(Iterable<int> indexes) =>
      delegate.emitEffectiveSequence(indexes);

  @override
  Stream<PlaybackEngineEvent> get sourceEvents => delegate.sourceEvents;

  @override
  Stream<just_audio.PlayerState> get playerStateStream =>
      delegate.playerStateStream;

  @override
  Stream<Duration> get positionStream => delegate.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      delegate.bufferedPositionStream;

  @override
  Stream<Duration?> get durationStream => delegate.durationStream;

  @override
  Stream<int?> get currentIndexStream => delegate.currentIndexStream;

  @override
  Stream<List<int>> get effectiveSequenceStream =>
      delegate.effectiveSequenceStream;

  @override
  Stream<double> get speedStream => delegate.speedStream;

  @override
  Stream<just_audio.LoopMode> get loopModeStream => delegate.loopModeStream;

  @override
  Stream<bool> get shuffleModeEnabledStream =>
      delegate.shuffleModeEnabledStream;

  @override
  Stream<just_audio.PlayerException> get errorStream => delegate.errorStream;

  @override
  Future<void> load(
    List<just_audio.AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  }) => delegate.load(
    sources,
    initialIndex: initialIndex,
    sourceGeneration: sourceGeneration,
  );

  @override
  Future<void> interruptLoad() => delegate.interruptLoad();

  @override
  Future<void> play() => delegate.play();

  @override
  Future<void> pause() => delegate.pause();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> seek(Duration position, {int? index}) =>
      delegate.seek(position, index: index);

  @override
  Future<void> setSpeed(double speed) => delegate.setSpeed(speed);

  @override
  Future<void> setLoopMode(just_audio.LoopMode mode) =>
      delegate.setLoopMode(mode);

  @override
  Future<void> setShuffleEnabled(bool enabled) {
    delegate.setShuffleEnabled(enabled);
    return shuffleAction?.call(enabled) ?? Future<void>.value();
  }

  @override
  Future<void> dispose() => delegate.dispose();
}
