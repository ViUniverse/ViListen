// SPDX-License-Identifier: Apache-2.0

import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

/// Immutable playback state published by the player domain.
///
/// This value object stores the state supplied by the playback reducer. It does
/// not validate or infer engine transitions when fields are changed.
final class PlaybackSnapshot {
  factory PlaybackSnapshot({
    required PlayerItem? currentItem,
    required List<PlayerItem> queue,
    required int? currentIndex,
    required PlaybackProcessingState processingState,
    required bool playing,
    required Duration position,
    required Duration bufferedPosition,
    required Duration duration,
    required double speed,
    required PlayerRepeatMode repeatMode,
    required bool shuffleEnabled,
    required PlayerFailure? failure,
  }) => PlaybackSnapshot._(
    currentItem: currentItem,
    queue: List<PlayerItem>.unmodifiable(queue),
    currentIndex: currentIndex,
    processingState: processingState,
    playing: playing,
    position: position,
    bufferedPosition: bufferedPosition,
    duration: duration,
    speed: speed,
    repeatMode: repeatMode,
    shuffleEnabled: shuffleEnabled,
    failure: failure,
  );

  const PlaybackSnapshot._({
    required this.currentItem,
    required this.queue,
    required this.currentIndex,
    required this.processingState,
    required this.playing,
    required this.position,
    required this.bufferedPosition,
    required this.duration,
    required this.speed,
    required this.repeatMode,
    required this.shuffleEnabled,
    required this.failure,
  });

  /// The only canonical idle snapshot.
  static const PlaybackSnapshot idle = PlaybackSnapshot._(
    currentItem: null,
    queue: <PlayerItem>[],
    currentIndex: null,
    processingState: PlaybackProcessingState.idle,
    playing: false,
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: Duration.zero,
    speed: 1.0,
    repeatMode: PlayerRepeatMode.off,
    shuffleEnabled: false,
    failure: null,
  );

  final PlayerItem? currentItem;
  final List<PlayerItem> queue;
  final int? currentIndex;
  final PlaybackProcessingState processingState;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final double speed;
  final PlayerRepeatMode repeatMode;
  final bool shuffleEnabled;
  final PlayerFailure? failure;

  /// Playback position normalized to the inclusive range from 0 to 1.
  ///
  /// A zero or negative duration represents an unknown duration.
  double get progress {
    final durationMicros = duration.inMicroseconds;
    if (durationMicros <= 0) {
      return 0.0;
    }

    final ratio = position.inMicroseconds / durationMicros;
    if (!ratio.isFinite || ratio <= 0) {
      return 0.0;
    }
    if (ratio >= 1) {
      return 1.0;
    }
    return ratio;
  }

  /// Time left in the current item, clamped to a non-negative duration.
  ///
  /// A zero or negative duration represents an unknown duration.
  Duration get remaining {
    if (duration <= Duration.zero) {
      return Duration.zero;
    }

    final boundedPosition = position <= Duration.zero
        ? Duration.zero
        : position >= duration
        ? duration
        : position;
    return duration - boundedPosition;
  }

  bool get isBuffering => processingState == PlaybackProcessingState.buffering;

  bool get isAudible =>
      playing && processingState == PlaybackProcessingState.ready;

  bool get hasNext {
    final index = currentIndex;
    return index != null && index >= 0 && index < queue.length - 1;
  }

  bool get hasPrevious {
    final index = currentIndex;
    return index != null && index > 0 && index < queue.length;
  }

  bool get isCompleted => processingState == PlaybackProcessingState.completed;

  static const Object _unset = Object();

  PlaybackSnapshot copyWith({
    Object? currentItem = _unset,
    List<PlayerItem>? queue,
    Object? currentIndex = _unset,
    PlaybackProcessingState? processingState,
    bool? playing,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    double? speed,
    PlayerRepeatMode? repeatMode,
    bool? shuffleEnabled,
    Object? failure = _unset,
  }) => PlaybackSnapshot(
    currentItem: identical(currentItem, _unset)
        ? this.currentItem
        : currentItem as PlayerItem?,
    queue: queue ?? this.queue,
    currentIndex: identical(currentIndex, _unset)
        ? this.currentIndex
        : currentIndex as int?,
    processingState: processingState ?? this.processingState,
    playing: playing ?? this.playing,
    position: position ?? this.position,
    bufferedPosition: bufferedPosition ?? this.bufferedPosition,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    repeatMode: repeatMode ?? this.repeatMode,
    shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
    failure: identical(failure, _unset)
        ? this.failure
        : failure as PlayerFailure?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSnapshot &&
          other.currentItem == currentItem &&
          _listEquals(other.queue, queue) &&
          other.currentIndex == currentIndex &&
          other.processingState == processingState &&
          other.playing == playing &&
          other.position == position &&
          other.bufferedPosition == bufferedPosition &&
          other.duration == duration &&
          other.speed == speed &&
          other.repeatMode == repeatMode &&
          other.shuffleEnabled == shuffleEnabled &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(
    currentItem,
    Object.hashAll(queue),
    currentIndex,
    processingState,
    playing,
    position,
    bufferedPosition,
    duration,
    speed,
    repeatMode,
    shuffleEnabled,
    failure,
  );
}

bool _listEquals(List<PlayerItem> first, List<PlayerItem> second) {
  if (first.length != second.length) {
    return false;
  }

  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }

  return true;
}
