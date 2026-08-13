// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'playback_engine.dart';

/// Production [PlaybackEngine] backed by exactly one [AudioPlayer].
final class JustAudioPlaybackEngine implements PlaybackEngine {
  JustAudioPlaybackEngine() {
    _sourceEventSubscriptions.addAll([
      _player.playerStateStream.listen(
        (value) => _emitSourceEvent(PlaybackEngineEventType.playerState, value),
      ),
      _player.positionStream.listen(
        (value) => _emitSourceEvent(PlaybackEngineEventType.position, value),
      ),
      _player.bufferedPositionStream.listen(
        (value) =>
            _emitSourceEvent(PlaybackEngineEventType.bufferedPosition, value),
      ),
      _player.durationStream.listen(
        (value) => _emitSourceEvent(PlaybackEngineEventType.duration, value),
      ),
      _player.currentIndexStream.listen(
        (value) =>
            _emitSourceEvent(PlaybackEngineEventType.currentIndex, value),
      ),
      _player.sequenceStateStream.listen(
        (value) => _emitSourceEvent(
          PlaybackEngineEventType.effectiveSequence,
          _effectiveSequence(value),
        ),
      ),
      _player.speedStream.listen(
        (value) => _emitSourceEvent(PlaybackEngineEventType.speed, value),
      ),
      _player.loopModeStream.listen(
        (value) => _emitSourceEvent(PlaybackEngineEventType.loopMode, value),
      ),
      _player.shuffleModeEnabledStream.listen(
        (value) =>
            _emitSourceEvent(PlaybackEngineEventType.shuffleEnabled, value),
      ),
      _player.errorStream.listen(
        (value) => _emitSourceEvent(PlaybackEngineEventType.error, value),
      ),
    ]);
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<PlaybackEngineEvent> _sourceEventController =
      StreamController<PlaybackEngineEvent>.broadcast(sync: true);
  final List<StreamSubscription<dynamic>> _sourceEventSubscriptions =
      <StreamSubscription<dynamic>>[];

  Future<void>? _disposeFuture;
  int _loadRevision = 0;
  int _sourceGeneration = 0;

  @override
  Stream<PlaybackEngineEvent> get sourceEvents => _sourceEventController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  @override
  Stream<List<int>> get effectiveSequenceStream =>
      _player.sequenceStateStream.map(_effectiveSequence);

  @override
  Stream<double> get speedStream => _player.speedStream;

  @override
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;

  @override
  Stream<bool> get shuffleModeEnabledStream => _player.shuffleModeEnabledStream;

  @override
  Stream<PlayerException> get errorStream => _player.errorStream;

  @override
  Future<void> load(
    List<AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  }) async {
    final revision = ++_loadRevision;
    // just_audio retains its playing flag across setAudioSources. Pause first
    // so replacement loads cannot start the new source before handler commit.
    await _player.pause();
    _checkLoadRevision(revision);
    await _player.setAudioSources(
      sources,
      preload: true,
      initialIndex: initialIndex,
    );
    _checkLoadRevision(revision);
    _sourceGeneration = sourceGeneration;
    _emitCurrentGraphState();
  }

  @override
  Future<void> interruptLoad() async {
    _loadRevision += 1;
    await _player.stop();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    final state = _player.playerState;
    if (state.playing || state.processingState != ProcessingState.idle) {
      throw const PlaybackStopNotConfirmed();
    }
  }

  @override
  Future<void> seek(Duration position, {int? index}) =>
      _player.seek(position, index: index);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);

  @override
  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    _loadRevision += 1;
    return _disposeFuture = _disposeResources();
  }

  Future<void> _disposeResources() async {
    try {
      await Future.wait<void>(
        _sourceEventSubscriptions.map((subscription) => subscription.cancel()),
      );
    } finally {
      try {
        await _sourceEventController.close();
      } finally {
        await _player.dispose();
      }
    }
  }

  void _emitSourceEvent(PlaybackEngineEventType type, Object? value) {
    if (_sourceEventController.isClosed) {
      return;
    }
    _sourceEventController.add((
      sourceGeneration: _sourceGeneration,
      type: type,
      value: value,
    ));
  }

  void _emitCurrentGraphState() {
    _emitSourceEvent(PlaybackEngineEventType.playerState, _player.playerState);
    _emitSourceEvent(PlaybackEngineEventType.position, _player.position);
    _emitSourceEvent(
      PlaybackEngineEventType.bufferedPosition,
      _player.bufferedPosition,
    );
    _emitSourceEvent(PlaybackEngineEventType.duration, _player.duration);
    _emitSourceEvent(
      PlaybackEngineEventType.currentIndex,
      _player.currentIndex,
    );
    _emitSourceEvent(
      PlaybackEngineEventType.effectiveSequence,
      _effectiveSequence(_player.sequenceState),
    );
    _emitSourceEvent(PlaybackEngineEventType.speed, _player.speed);
    _emitSourceEvent(PlaybackEngineEventType.loopMode, _player.loopMode);
    _emitSourceEvent(
      PlaybackEngineEventType.shuffleEnabled,
      _player.shuffleModeEnabled,
    );
  }

  void _checkLoadRevision(int revision) {
    if (revision != _loadRevision) {
      throw PlayerInterruptedException('Loading interrupted');
    }
  }

  static List<int> _effectiveSequence(SequenceState state) {
    final indexes = state.shuffleModeEnabled
        ? state.shuffleIndices
        : List<int>.generate(state.sequence.length, (index) => index);
    return List<int>.unmodifiable(indexes);
  }
}
