// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:just_audio/just_audio.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import 'player_call_recorder.dart';

final class FakeLoadRequest {
  FakeLoadRequest({
    required List<AudioSource> sources,
    required this.initialIndex,
  }) : sources = List<AudioSource>.unmodifiable(sources);

  final List<AudioSource> sources;
  final int initialIndex;
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  void complete() => _completer.complete();

  void completeError(Object error, [StackTrace? stackTrace]) =>
      _completer.completeError(error, stackTrace ?? StackTrace.current);
}

final class FakeLoadInterrupted implements Exception {
  @override
  String toString() => 'FakeLoadInterrupted';
}

/// Platform-free test double for [PlaybackEngine].
///
/// Engine events are emitted one stream at a time. Loads remain pending until
/// the test completes the corresponding [FakeLoadRequest], which makes late
/// success and error results deterministic.
final class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({
    PlayerCallRecorder? recorder,
    this.playAction,
    this.pauseAction,
    this.seekAction,
    this.stopAction,
    this.setSpeedAction,
    this.setLoopModeAction,
    this.setShuffleEnabledAction,
    this.emitStopConfirmation = true,
    this.interruptCompletesLoad = true,
  }) : recorder = recorder ?? PlayerCallRecorder();

  final PlayerCallRecorder recorder;
  Future<void> Function()? playAction;
  Future<void> Function()? pauseAction;
  Future<void> Function(Duration position, {int? index})? seekAction;
  Future<void> Function()? stopAction;
  Future<void> Function(double speed)? setSpeedAction;
  Future<void> Function(LoopMode mode)? setLoopModeAction;
  Future<void> Function(bool enabled)? setShuffleEnabledAction;
  bool emitStopConfirmation;
  final bool interruptCompletesLoad;

  int _sourceGeneration = 0;

  final StreamController<PlaybackEngineEvent> _sourceEventController =
      StreamController<PlaybackEngineEvent>.broadcast(sync: true);

  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast(sync: true);
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
  final StreamController<LoopMode> _loopModeController =
      StreamController<LoopMode>.broadcast(sync: true);
  final StreamController<bool> _shuffleModeController =
      StreamController<bool>.broadcast(sync: true);
  final StreamController<PlayerException> _errorController =
      StreamController<PlayerException>.broadcast(sync: true);

  final List<FakeLoadRequest> _loadRequests = <FakeLoadRequest>[];
  List<AudioSource> _graphSources = const <AudioSource>[];
  FakeLoadRequest? _activeLoadRequest;

  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Stream<PlaybackEngineEvent> get sourceEvents => _sourceEventController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

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
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;

  @override
  Stream<bool> get shuffleModeEnabledStream => _shuffleModeController.stream;

  @override
  Stream<PlayerException> get errorStream => _errorController.stream;

  List<FakeLoadRequest> get loadRequests =>
      List<FakeLoadRequest>.unmodifiable(_loadRequests);

  List<AudioSource> get graphSources =>
      List<AudioSource>.unmodifiable(_graphSources);

  List<String?> get graphItemIds => _graphSources
      .map((source) {
        final tag = source is UriAudioSource ? source.tag : null;
        return tag is audio_service.MediaItem ? tag.id : null;
      })
      .toList(growable: false);

  List<RecordedPlayerCall> get calls => recorder.calls;

  int callCountFor(String name) => recorder.callCountFor(name);

  int disposeCount = 0;

  @override
  Future<void> load(
    List<AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  }) {
    _checkNotDisposed();
    _sourceGeneration = sourceGeneration;
    final request = FakeLoadRequest(
      sources: sources,
      initialIndex: initialIndex,
    );
    _loadRequests.add(request);
    _graphSources = request.sources;
    _activeLoadRequest = request;
    recorder.record(
      'load',
      arguments: <String, Object?>{
        'sources': request.sources,
        'initialIndex': initialIndex,
      },
    );
    return request.future;
  }

  @override
  Future<void> interruptLoad() {
    _checkNotDisposed();
    recorder.record('interruptLoad');
    final request = _activeLoadRequest;
    if (interruptCompletesLoad && request != null && !request.isCompleted) {
      _activeLoadRequest = null;
      request.completeError(FakeLoadInterrupted());
    }
    return Future<void>.value();
  }

  @override
  Future<void> play() {
    _checkNotDisposed();
    recorder.record('play');
    return playAction?.call() ?? Future<void>.value();
  }

  @override
  Future<void> pause() {
    _checkNotDisposed();
    recorder.record('pause');
    return pauseAction?.call() ?? Future<void>.value();
  }

  @override
  Future<void> stop() {
    _checkNotDisposed();
    recorder.record('stop');
    final operation = stopAction?.call() ?? Future<void>.value();
    return operation.then<void>((_) {
      if (emitStopConfirmation) {
        emitPlayerState(
          PlayerState(false, ProcessingState.idle),
          sourceGeneration: _sourceGeneration,
        );
      }
    });
  }

  @override
  Future<void> seek(Duration position, {int? index}) {
    _checkNotDisposed();
    if (index != null && (index < 0 || index >= _graphSources.length)) {
      throw RangeError.index(index, _graphSources, 'index');
    }
    recorder.record(
      'seek',
      arguments: <String, Object?>{'position': position, 'index': index},
    );
    return seekAction?.call(position, index: index) ?? Future<void>.value();
  }

  @override
  Future<void> setSpeed(double speed) {
    _checkNotDisposed();
    recorder.record('setSpeed', arguments: <String, Object?>{'speed': speed});
    return setSpeedAction?.call(speed) ?? Future<void>.value();
  }

  @override
  Future<void> setLoopMode(LoopMode mode) {
    _checkNotDisposed();
    recorder.record('setLoopMode', arguments: <String, Object?>{'mode': mode});
    return setLoopModeAction?.call(mode) ?? Future<void>.value();
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) {
    _checkNotDisposed();
    recorder.record(
      'setShuffleEnabled',
      arguments: <String, Object?>{'enabled': enabled},
    );
    return setShuffleEnabledAction?.call(enabled) ?? Future<void>.value();
  }

  void emitPlayerState(PlayerState state, {int? sourceGeneration}) {
    _checkNotDisposed();
    _playerStateController.add(state);
    _emitSourceEvent(
      PlaybackEngineEventType.playerState,
      state,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitPosition(Duration position, {int? sourceGeneration}) {
    _checkNotDisposed();
    _positionController.add(position);
    _emitSourceEvent(
      PlaybackEngineEventType.position,
      position,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitBufferedPosition(Duration position, {int? sourceGeneration}) {
    _checkNotDisposed();
    _bufferedPositionController.add(position);
    _emitSourceEvent(
      PlaybackEngineEventType.bufferedPosition,
      position,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitDuration(Duration? duration, {int? sourceGeneration}) {
    _checkNotDisposed();
    _durationController.add(duration);
    _emitSourceEvent(
      PlaybackEngineEventType.duration,
      duration,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitCurrentIndex(int? index, {int? sourceGeneration}) {
    _checkNotDisposed();
    _currentIndexController.add(index);
    _emitSourceEvent(
      PlaybackEngineEventType.currentIndex,
      index,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitEffectiveSequence(Iterable<int> indexes, {int? sourceGeneration}) {
    _checkNotDisposed();
    final sequence = List<int>.unmodifiable(indexes);
    _effectiveSequenceController.add(sequence);
    _emitSourceEvent(
      PlaybackEngineEventType.effectiveSequence,
      sequence,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitSpeed(double speed, {int? sourceGeneration}) {
    _checkNotDisposed();
    _speedController.add(speed);
    _emitSourceEvent(
      PlaybackEngineEventType.speed,
      speed,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitLoopMode(LoopMode mode, {int? sourceGeneration}) {
    _checkNotDisposed();
    _loopModeController.add(mode);
    _emitSourceEvent(
      PlaybackEngineEventType.loopMode,
      mode,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitShuffleModeEnabled(bool enabled, {int? sourceGeneration}) {
    _checkNotDisposed();
    _shuffleModeController.add(enabled);
    _emitSourceEvent(
      PlaybackEngineEventType.shuffleEnabled,
      enabled,
      sourceGeneration: sourceGeneration,
    );
  }

  void emitError(PlayerException error, {int? sourceGeneration}) {
    _checkNotDisposed();
    _errorController.add(error);
    _emitSourceEvent(
      PlaybackEngineEventType.error,
      error,
      sourceGeneration: sourceGeneration,
    );
  }

  void _emitSourceEvent(
    PlaybackEngineEventType type,
    Object? value, {
    int? sourceGeneration,
  }) {
    _sourceEventController.add((
      sourceGeneration: sourceGeneration ?? _sourceGeneration,
      type: type,
      value: value,
    ));
  }

  @override
  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    _disposed = true;
    disposeCount += 1;
    return _disposeFuture = Future.wait<void>([
      _playerStateController.close(),
      _positionController.close(),
      _bufferedPositionController.close(),
      _durationController.close(),
      _currentIndexController.close(),
      _effectiveSequenceController.close(),
      _speedController.close(),
      _loopModeController.close(),
      _shuffleModeController.close(),
      _errorController.close(),
      _sourceEventController.close(),
    ]);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FakePlaybackEngine has been disposed.');
    }
  }
}
