// SPDX-License-Identifier: Apache-2.0

import 'package:just_audio/just_audio.dart';

import 'playback_engine.dart';

/// Production [PlaybackEngine] backed by exactly one [AudioPlayer].
final class JustAudioPlaybackEngine implements PlaybackEngine {
  final AudioPlayer _player = AudioPlayer();

  Future<void>? _disposeFuture;

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
  }) async {
    await _player.setAudioSources(
      sources,
      preload: true,
      initialIndex: initialIndex,
    );
  }

  @override
  Future<void> interruptLoad() => _player.stop();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

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

    return _disposeFuture = _player.dispose();
  }

  static List<int> _effectiveSequence(SequenceState state) {
    final indexes = state.shuffleModeEnabled
        ? state.shuffleIndices
        : List<int>.generate(state.sequence.length, (index) => index);
    return List<int>.unmodifiable(indexes);
  }
}
