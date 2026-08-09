// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

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
  FakePlaybackEngine({PlayerCallRecorder? recorder})
    : recorder = recorder ?? PlayerCallRecorder();

  final PlayerCallRecorder recorder;

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
  FakeLoadRequest? _activeLoadRequest;

  Future<void>? _disposeFuture;
  bool _disposed = false;

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

  List<RecordedPlayerCall> get calls => recorder.calls;

  int callCountFor(String name) => recorder.callCountFor(name);

  int disposeCount = 0;

  @override
  Future<void> load(List<AudioSource> sources, {required int initialIndex}) {
    _checkNotDisposed();
    final request = FakeLoadRequest(
      sources: sources,
      initialIndex: initialIndex,
    );
    _loadRequests.add(request);
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
    if (request != null && !request.isCompleted) {
      _activeLoadRequest = null;
      request.completeError(FakeLoadInterrupted());
    }
    return Future<void>.value();
  }

  @override
  Future<void> play() {
    _checkNotDisposed();
    recorder.record('play');
    return Future<void>.value();
  }

  @override
  Future<void> pause() {
    _checkNotDisposed();
    recorder.record('pause');
    return Future<void>.value();
  }

  @override
  Future<void> stop() {
    _checkNotDisposed();
    recorder.record('stop');
    return Future<void>.value();
  }

  @override
  Future<void> seek(Duration position, {int? index}) {
    _checkNotDisposed();
    recorder.record(
      'seek',
      arguments: <String, Object?>{'position': position, 'index': index},
    );
    return Future<void>.value();
  }

  @override
  Future<void> setSpeed(double speed) {
    _checkNotDisposed();
    recorder.record('setSpeed', arguments: <String, Object?>{'speed': speed});
    return Future<void>.value();
  }

  @override
  Future<void> setLoopMode(LoopMode mode) {
    _checkNotDisposed();
    recorder.record('setLoopMode', arguments: <String, Object?>{'mode': mode});
    return Future<void>.value();
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) {
    _checkNotDisposed();
    recorder.record(
      'setShuffleEnabled',
      arguments: <String, Object?>{'enabled': enabled},
    );
    return Future<void>.value();
  }

  void emitPlayerState(PlayerState state) {
    _checkNotDisposed();
    _playerStateController.add(state);
  }

  void emitPosition(Duration position) {
    _checkNotDisposed();
    _positionController.add(position);
  }

  void emitBufferedPosition(Duration position) {
    _checkNotDisposed();
    _bufferedPositionController.add(position);
  }

  void emitDuration(Duration? duration) {
    _checkNotDisposed();
    _durationController.add(duration);
  }

  void emitCurrentIndex(int? index) {
    _checkNotDisposed();
    _currentIndexController.add(index);
  }

  void emitEffectiveSequence(Iterable<int> indexes) {
    _checkNotDisposed();
    _effectiveSequenceController.add(List<int>.unmodifiable(indexes));
  }

  void emitSpeed(double speed) {
    _checkNotDisposed();
    _speedController.add(speed);
  }

  void emitLoopMode(LoopMode mode) {
    _checkNotDisposed();
    _loopModeController.add(mode);
  }

  void emitShuffleModeEnabled(bool enabled) {
    _checkNotDisposed();
    _shuffleModeController.add(enabled);
  }

  void emitError(PlayerException error) {
    _checkNotDisposed();
    _errorController.add(error);
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
    ]);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FakePlaybackEngine has been disposed.');
    }
  }
}
