// SPDX-License-Identifier: Apache-2.0

import 'package:just_audio/just_audio.dart';

enum PlaybackEngineEventType {
  playerState,
  position,
  bufferedPosition,
  duration,
  currentIndex,
  effectiveSequence,
  speed,
  loopMode,
  shuffleEnabled,
  error,
}

typedef PlaybackEngineEvent = ({
  int sourceGeneration,
  PlaybackEngineEventType type,
  Object? value,
});

final class PlaybackStopNotConfirmed implements Exception {
  const PlaybackStopNotConfirmed();

  @override
  String toString() =>
      'PlaybackStopNotConfirmed: the engine did not confirm idle playback.';
}

/// Internal seam between the player handler and the concrete audio engine.
///
/// The port deliberately does not expose [AudioPlayer]. The handler owns
/// playback policy and uses this interface only for engine state, timeline,
/// queue-index/options events, and the commands it must issue.
abstract interface class PlaybackEngine {
  /// Normalized engine events tagged with the source generation that owns them.
  ///
  /// Raw streams remain exposed for low-level engine seam tests, but handler
  /// state ownership must be decided from this tagged stream.
  Stream<PlaybackEngineEvent> get sourceEvents;

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

  /// Loads sources paused and waits for the operation to complete.
  ///
  /// An existing playing source must be paused before replacement. Autoplay is
  /// intentionally not part of this operation. The handler must commit and
  /// publish the loaded queue before it issues [play]. Events emitted while
  /// the graph is being replaced must remain owned by the prior source; the
  /// supplied generation becomes current only after the new graph is ready.
  Future<void> load(
    List<AudioSource> sources, {
    required int initialIndex,
    required int sourceGeneration,
  });

  /// Interrupts the currently pending [load] and completes its handshake.
  ///
  /// A source-changing command must be able to release the coordinator graph
  /// lane even when the engine's original load Future is still pending.
  Future<void> interruptLoad();

  Future<void> play();

  Future<void> pause();

  /// Stops playback and completes only after the engine reports
  /// `playing == false` with [ProcessingState.idle].
  ///
  /// Implementations must throw when the command Future completes without
  /// that engine confirmation. A successful Future is the handler's sole Stop
  /// confirmation authority; source-event timing must not be checked again.
  Future<void> stop();

  Future<void> seek(Duration position, {int? index});

  Future<void> setSpeed(double speed);

  Future<void> setLoopMode(LoopMode mode);

  Future<void> setShuffleEnabled(bool enabled);

  Future<void> dispose();
}
