// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import '../support/player_test_data.dart';

void main() {
  late _RacePlaybackEngine engine;
  late AppAudioHandler handler;

  void createHandler({required bool interruptWithError}) {
    engine = _RacePlaybackEngine(interruptWithError: interruptWithError);
    handler = AppAudioHandler(engine);
  }

  tearDown(() async {
    await handler.dispose();
  });

  test('latest load wins when A succeeds after B is ready', () async {
    createHandler(interruptWithError: false);
    final publications = await _capturePublications(handler);
    final itemA = testPlayerItem(id: 'race-track-a');
    final itemB = testPlayerItem(id: 'race-track-b');

    final loadA = handler.handleLoadQueue([itemA], 0, false, CommandSource.ui);
    await pumpEventQueue();
    final requestA = engine.loadRequests.single;

    final loadB = handler.handleLoadQueue([itemB], 0, false, CommandSource.ui);
    await pumpEventQueue();

    expect(engine.interruptCount, 1);
    expect(engine.loadRequests, hasLength(2));
    expect(requestA.isCompleted, isFalse);

    engine.loadRequests[1].complete();
    await loadB;
    await pumpEventQueue();

    // A completes after B has already committed. Its result must be inert.
    requestA.complete();
    await loadA;
    await pumpEventQueue();

    _expectOnlyItemB(publications, itemA.id, itemB.id);
  });

  test('stale interrupted error from A is not exposed as a failure', () async {
    createHandler(interruptWithError: true);
    final publications = await _capturePublications(handler);
    final itemA = testPlayerItem(id: 'interrupted-track-a');
    final itemB = testPlayerItem(id: 'interrupted-track-b');

    final loadA = handler.handleLoadQueue([itemA], 0, false, CommandSource.ui);
    await pumpEventQueue();

    final loadB = handler.handleLoadQueue([itemB], 0, false, CommandSource.ui);
    await pumpEventQueue();

    // The old Future completes with an interruption error, but the handler
    // has already invalidated A's generation.
    await loadA;
    expect(engine.loadRequests.first.isCompleted, isTrue);
    expect(engine.loadRequests, hasLength(2));

    engine.loadRequests[1].complete();
    await loadB;
    await pumpEventQueue();

    _expectOnlyItemB(publications, itemA.id, itemB.id);
    expect(
      publications.playbackStates,
      isNot(contains(audio_service.AudioProcessingState.error)),
    );
  });

  test('B invalidates A after A is ready but before A commit runs', () async {
    createHandler(interruptWithError: false);
    final publications = await _capturePublications(handler);
    final itemA = testPlayerItem(id: 'precommit-track-a');
    final itemB = testPlayerItem(id: 'precommit-track-b');

    final loadA = handler.handleLoadQueue([itemA], 0, false, CommandSource.ui);
    await pumpEventQueue();

    // Do not yield between A's completion and starting B. This exercises the
    // generation check at the load-to-commit boundary.
    engine.loadRequests.single.complete();
    final loadB = handler.handleLoadQueue([itemB], 0, false, CommandSource.ui);
    await pumpEventQueue();

    expect(engine.loadRequests, hasLength(2));
    await loadA;

    engine.loadRequests[1].complete();
    await loadB;
    await pumpEventQueue();

    _expectOnlyItemB(publications, itemA.id, itemB.id);
  });
}

Future<_Publications> _capturePublications(AppAudioHandler handler) async {
  final snapshots = <PlaybackSnapshot>[];
  final mediaItemIds = <String?>[];
  final queueIds = <List<String>>[];
  final playbackStates = <audio_service.AudioProcessingState>[];

  final snapshotSubscription = handler.snapshots.listen(snapshots.add);
  final mediaItemSubscription = handler.mediaItem.listen(
    (item) => mediaItemIds.add(item?.id),
  );
  final queueSubscription = handler.queue.listen(
    (items) => queueIds.add(items.map((item) => item.id).toList()),
  );
  final playbackStateSubscription = handler.playbackState.listen(
    (state) => playbackStates.add(state.processingState),
  );

  addTearDown(snapshotSubscription.cancel);
  addTearDown(mediaItemSubscription.cancel);
  addTearDown(queueSubscription.cancel);
  addTearDown(playbackStateSubscription.cancel);
  await pumpEventQueue();

  return _Publications(
    snapshots: snapshots,
    mediaItemIds: mediaItemIds,
    queueIds: queueIds,
    playbackStates: playbackStates,
  );
}

void _expectOnlyItemB(
  _Publications publications,
  String itemAId,
  String itemBId,
) {
  for (final snapshot in publications.snapshots) {
    expect(snapshot.currentItem?.id, isNot(equals(itemAId)));
    expect(snapshot.queue.map((item) => item.id), isNot(contains(itemAId)));
    expect(snapshot.failure, isNull);
  }

  final snapshotsWithItem = publications.snapshots
      .where((snapshot) => snapshot.currentItem != null)
      .map((snapshot) => snapshot.currentItem!.id)
      .toList();
  final snapshotsWithQueue = publications.snapshots
      .where((snapshot) => snapshot.queue.isNotEmpty)
      .map((snapshot) => snapshot.queue.map((item) => item.id).toList())
      .toList();
  final mediaItemPublications = publications.mediaItemIds
      .whereType<String>()
      .toList();
  final queuePublications = publications.queueIds
      .where((ids) => ids.isNotEmpty)
      .toList();

  expect(snapshotsWithItem, [itemBId]);
  expect(snapshotsWithQueue, [
    <String>[itemBId],
  ]);
  expect(mediaItemPublications, [itemBId]);
  expect(queuePublications, [
    <String>[itemBId],
  ]);
}

final class _Publications {
  const _Publications({
    required this.snapshots,
    required this.mediaItemIds,
    required this.queueIds,
    required this.playbackStates,
  });

  final List<PlaybackSnapshot> snapshots;
  final List<String?> mediaItemIds;
  final List<List<String>> queueIds;
  final List<audio_service.AudioProcessingState> playbackStates;
}

final class _RaceLoadRequest {
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void complete() => _completer.complete();

  void completeError(Object error) => _completer.completeError(error);
}

final class _RacePlaybackEngine implements PlaybackEngine {
  _RacePlaybackEngine({required this.interruptWithError});

  final bool interruptWithError;
  final List<_RaceLoadRequest> loadRequests = <_RaceLoadRequest>[];

  final StreamController<just_audio.PlayerState> _playerStateController =
      StreamController<just_audio.PlayerState>.broadcast(sync: true);
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration> _bufferedPositionController =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast(sync: true);
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast(sync: true);
  final StreamController<List<int>> _effectiveSequenceController =
      StreamController<List<int>>.broadcast(sync: true);
  final StreamController<double> _speedController =
      StreamController<double>.broadcast(sync: true);
  final StreamController<just_audio.LoopMode> _loopModeController =
      StreamController<just_audio.LoopMode>.broadcast(sync: true);
  final StreamController<bool> _shuffleController =
      StreamController<bool>.broadcast(sync: true);
  final StreamController<just_audio.PlayerException> _errorController =
      StreamController<just_audio.PlayerException>.broadcast(sync: true);
  final StreamController<PlaybackEngineEvent> _sourceEventController =
      StreamController<PlaybackEngineEvent>.broadcast(sync: true);

  _RaceLoadRequest? _activeLoadRequest;
  Future<void>? _disposeFuture;
  int interruptCount = 0;

  @override
  Stream<PlaybackEngineEvent> get sourceEvents => _sourceEventController.stream;

  @override
  Stream<just_audio.PlayerState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  Stream<List<int>> get effectiveSequenceStream =>
      _effectiveSequenceController.stream;

  @override
  Stream<double> get speedStream => _speedController.stream;

  @override
  Stream<just_audio.LoopMode> get loopModeStream => _loopModeController.stream;

  @override
  Stream<bool> get shuffleModeEnabledStream => _shuffleController.stream;

  @override
  Stream<just_audio.PlayerException> get errorStream => _errorController.stream;

  @override
  Future<void> load(
    List<just_audio.AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  }) {
    final request = _RaceLoadRequest();
    loadRequests.add(request);
    _activeLoadRequest = request;
    return request.future;
  }

  @override
  Future<void> interruptLoad() {
    interruptCount += 1;
    final request = _activeLoadRequest;
    _activeLoadRequest = null;
    if (interruptWithError && request != null && !request.isCompleted) {
      request.completeError(StateError('stale load interrupted'));
    }
    return Future<void>.value();
  }

  @override
  Future<void> play() => Future<void>.value();

  @override
  Future<void> pause() => Future<void>.value();

  @override
  Future<void> stop() => Future<void>.value();

  @override
  Future<void> seek(Duration position, {int? index}) => Future<void>.value();

  @override
  Future<void> setSpeed(double speed) => Future<void>.value();

  @override
  Future<void> setLoopMode(just_audio.LoopMode mode) => Future<void>.value();

  @override
  Future<void> setShuffleEnabled(bool enabled) => Future<void>.value();

  @override
  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    return _disposeFuture = Future.wait<void>([
      _playerStateController.close(),
      _positionController.close(),
      _bufferedPositionController.close(),
      _durationController.close(),
      _currentIndexController.close(),
      _effectiveSequenceController.close(),
      _speedController.close(),
      _loopModeController.close(),
      _shuffleController.close(),
      _errorController.close(),
      _sourceEventController.close(),
    ]);
  }
}
