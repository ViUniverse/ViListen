// SPDX-License-Identifier: Apache-2.0

import 'package:just_audio/just_audio.dart';

/// Internal seam between the player handler and the concrete audio engine.
///
/// The port deliberately does not expose [AudioPlayer]. The handler owns
/// playback policy and uses this interface only for engine state, timeline,
/// queue-index/options events, and the commands it must issue.
abstract interface class PlaybackEngine {
  Stream<PlayerState> get playerStateStream;

  Stream<Duration> get positionStream;

  Stream<Duration> get bufferedPositionStream;

  Stream<Duration?> get durationStream;

  Stream<int?> get currentIndexStream;

  /// Effective playback order expressed as indexes in the loaded sequence.
  Stream<List<int>> get effectiveSequenceStream;

  Stream<double> get speedStream;

  Stream<LoopMode> get loopModeStream;

  Stream<bool> get shuffleModeEnabledStream;

  Stream<PlayerException> get errorStream;

  /// Loads sources and waits for the engine's load operation to complete.
  ///
  /// Autoplay is intentionally not part of this operation. The handler must
  /// commit and publish the loaded queue before it issues [play].
  Future<void> load(List<AudioSource> sources, {required int initialIndex});

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position, {int? index});

  Future<void> setSpeed(double speed);

  Future<void> setLoopMode(LoopMode mode);

  Future<void> setShuffleEnabled(bool enabled);

  Future<void> dispose();
}
