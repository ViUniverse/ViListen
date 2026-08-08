// SPDX-License-Identifier: Apache-2.0

import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/playback_mappers.dart';

/// Accumulates independent engine events into complete playback snapshots.
///
/// The reducer does not publish snapshots, serialize commands, or make
/// generation decisions. The handler owns those concerns and decides when a
/// returned snapshot is safe to publish.
final class PlaybackSnapshotReducer {
  PlaybackSnapshotReducer({PlaybackSnapshot initial = PlaybackSnapshot.idle})
    : _latest = initial;

  PlaybackSnapshot _latest;

  PlaybackSnapshot get latest => _latest;

  /// Applies an engine player-state event without recovering a domain error.
  ///
  /// A ready/buffering event can arrive after an error. The error overlay is
  /// therefore passed through until [onLoadStarted] explicitly clears it.
  PlaybackSnapshot onPlayerState(just_audio.PlayerState state) {
    final failure = _latest.failure;
    _latest = _latest.copyWith(
      processingState: PlaybackMappers.mapProcessingState(
        state.processingState,
        failure: failure,
      ),
      playing: failure == null || failure.code == 'stopFailed'
          ? state.playing
          : false,
    );
    return _latest;
  }

  /// Starts a new load/retry recovery transition.
  ///
  /// Existing committed metadata and timeline are retained so a replacement
  /// load can keep the active item visible until its new state is committed.
  PlaybackSnapshot onLoadStarted() {
    _latest = _latest.copyWith(
      processingState: PlaybackProcessingState.loading,
      failure: null,
    );
    return _latest;
  }

  PlaybackSnapshot onPosition(Duration position) {
    _latest = _latest.copyWith(position: position);
    return _latest;
  }

  PlaybackSnapshot onBufferedPosition(Duration bufferedPosition) {
    _latest = _latest.copyWith(bufferedPosition: bufferedPosition);
    return _latest;
  }

  PlaybackSnapshot onDuration(Duration? duration) {
    final normalizedDuration = duration == null || duration <= Duration.zero
        ? Duration.zero
        : duration;
    _latest = _latest.copyWith(duration: normalizedDuration);
    return _latest;
  }

  /// Updates index and item as one consistent pair from the committed queue.
  PlaybackSnapshot onCurrentIndex(int? currentIndex) {
    final selection = _select(_latest.queue, currentIndex);
    _latest = _latest.copyWith(
      currentIndex: selection.index,
      currentItem: selection.item,
    );
    return _latest;
  }

  PlaybackSnapshot onSpeed(double speed) {
    _latest = _latest.copyWith(speed: speed);
    return _latest;
  }

  PlaybackSnapshot onLoopMode(just_audio.LoopMode loopMode) {
    _latest = _latest.copyWith(
      repeatMode: PlaybackMappers.fromEngineRepeat(loopMode),
    );
    return _latest;
  }

  PlaybackSnapshot onShuffleEnabled(bool enabled) {
    _latest = _latest.copyWith(shuffleEnabled: enabled);
    return _latest;
  }

  /// Applies a normalized failure with an explicit playing-state policy.
  ///
  /// Runtime/load/bootstrap failures set playing false. The stop-failure
  /// path passes true because the engine may still be playing.
  PlaybackSnapshot onFailure(
    PlayerFailure failure, {
    required bool preserveConfirmedPlaying,
  }) {
    _latest = _latest.copyWith(
      processingState: PlaybackProcessingState.error,
      playing: preserveConfirmedPlaying ? _latest.playing : false,
      failure: failure,
    );
    return _latest;
  }

  /// Atomically changes the effective queue and its selected item/index.
  PlaybackSnapshot commitQueue(
    List<PlayerItem> effectiveQueue, {
    required int? currentIndex,
  }) {
    final selection = _select(effectiveQueue, currentIndex);
    _latest = _latest.copyWith(
      queue: effectiveQueue,
      currentIndex: selection.index,
      currentItem: selection.item,
    );
    return _latest;
  }

  /// Atomically installs a complete pending snapshot, including its timeline.
  ///
  /// The caller should invoke this only after its latest-load/generation check
  /// succeeds. The supplied current item is intentionally ignored and
  /// reselected from the supplied queue and index.
  PlaybackSnapshot commitSnapshot(PlaybackSnapshot pending) {
    final selection = _select(pending.queue, pending.currentIndex);
    _latest = pending.copyWith(
      currentIndex: selection.index,
      currentItem: selection.item,
    );
    return _latest;
  }

  static ({int? index, PlayerItem? item}) _select(
    List<PlayerItem> queue,
    int? currentIndex,
  ) {
    if (currentIndex == null ||
        currentIndex < 0 ||
        currentIndex >= queue.length) {
      return (index: null, item: null);
    }

    return (index: currentIndex, item: queue[currentIndex]);
  }
}
