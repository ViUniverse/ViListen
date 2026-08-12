// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/infrastructure/load_generation_guard.dart';
import 'package:vi_listen/features/player/infrastructure/player_item_mapper.dart';

/// The last queue that has been committed by the playback engine.
///
/// A pending load must not replace this context until a later task confirms
/// and commits the engine result. Keeping this value separate from
/// [PendingLoadContext] is what preserves active metadata during a replace
/// load.
final class ActivePlaybackContext {
  ActivePlaybackContext({
    required Iterable<PlayerItem> logicalQueue,
    required Iterable<PlayerItem> effectiveQueue,
    required this.currentIndex,
    required this.position,
    required this.desiredPlaying,
  }) : logicalQueue = List<PlayerItem>.unmodifiable(logicalQueue),
       effectiveQueue = List<PlayerItem>.unmodifiable(effectiveQueue);

  factory ActivePlaybackContext.fromSnapshot({
    required Iterable<PlayerItem> logicalQueue,
    required Iterable<PlayerItem> effectiveQueue,
    required int? currentIndex,
    required Duration position,
    required bool desiredPlaying,
  }) => ActivePlaybackContext(
    logicalQueue: logicalQueue,
    effectiveQueue: effectiveQueue,
    currentIndex: currentIndex,
    position: position,
    desiredPlaying: desiredPlaying,
  );

  final List<PlayerItem> logicalQueue;
  final List<PlayerItem> effectiveQueue;
  final int? currentIndex;
  final Duration position;
  final bool desiredPlaying;
}

/// Immutable recovery target captured when a recoverable engine failure occurs.
///
/// The retry operation is intentionally deferred to PLR-081. Keeping this
/// context separate from the outward active snapshot ensures a replace failure
/// can retain A while retrying the failed target B.
final class RetryContext {
  RetryContext({
    required Iterable<PlayerItem> targetQueue,
    required this.targetIndex,
    required this.restorePosition,
    required this.desiredPlaying,
    required this.failureGeneration,
    required this.failureItemId,
  }) : targetQueue = List<PlayerItem>.unmodifiable(targetQueue);

  final List<PlayerItem> targetQueue;
  final int targetIndex;
  final Duration restorePosition;
  final bool desiredPlaying;
  final LoadGeneration? failureGeneration;
  final String failureItemId;
}

/// A validated queue that has started loading but is not current yet.
///
/// [sources] and [mediaItems] are derived from the same immutable
/// [targetQueue], in the same order. Neither projection is an outward commit;
/// the handler may only publish them after the matching generation is
/// engine-confirmed.
final class PendingLoadContext {
  PendingLoadContext({
    required Iterable<PlayerItem> targetQueue,
    required this.targetIndex,
    required this.autoplay,
    required this.desiredPlaying,
    required this.generation,
    required Iterable<just_audio.AudioSource> sources,
    required Iterable<audio_service.MediaItem> mediaItems,
    PendingLoadAccumulator? engineEvents,
  }) : targetQueue = List<PlayerItem>.unmodifiable(targetQueue),
       sources = List<just_audio.AudioSource>.unmodifiable(sources),
       mediaItems = List<audio_service.MediaItem>.unmodifiable(mediaItems),
       engineEvents = engineEvents ?? PendingLoadAccumulator(generation);

  factory PendingLoadContext.fromItems({
    required Iterable<PlayerItem> items,
    required int targetIndex,
    required bool autoplay,
    required LoadGeneration generation,
  }) {
    final targetQueue = List<PlayerItem>.unmodifiable(items);
    final sources = <just_audio.AudioSource>[];
    final mediaItems = <audio_service.MediaItem>[];

    for (final item in targetQueue) {
      mediaItems.add(PlayerItemMapper.toMediaItem(item));
      sources.add(PlayerItemMapper.toAudioSource(item));
    }

    return PendingLoadContext(
      targetQueue: targetQueue,
      targetIndex: targetIndex,
      autoplay: autoplay,
      desiredPlaying: autoplay,
      generation: generation,
      sources: sources,
      mediaItems: mediaItems,
    );
  }

  final List<PlayerItem> targetQueue;
  final int targetIndex;
  final bool autoplay;

  /// Latest Play/Pause intent for this load generation.
  ///
  /// This starts from [autoplay], but direct Play/Pause commands may update it
  /// while the engine is still loading. The target is committed paused first;
  /// only this final value may trigger post-commit Play.
  bool desiredPlaying;
  final LoadGeneration generation;
  final List<just_audio.AudioSource> sources;
  final List<audio_service.MediaItem> mediaItems;
  final PendingLoadAccumulator engineEvents;
}

/// Engine-side observations collected while a load is pending.
///
/// These values are deliberately separate from [PlaybackSnapshot]. They are
/// available to the later latest-generation commit, but cannot change the
/// active outward snapshot while the request is still pending.
final class PendingLoadAccumulator {
  PendingLoadAccumulator([this.generation]);

  final LoadGeneration? generation;

  just_audio.PlayerState? playerState;
  Duration? position;
  Duration? bufferedPosition;
  Duration? duration;
  int? currentIndex;
  double? speed;
  just_audio.LoopMode? loopMode;
  bool? shuffleEnabled;

  bool hasPlayerState = false;
  bool hasPosition = false;
  bool hasBufferedPosition = false;
  bool hasDuration = false;
  bool hasCurrentIndex = false;
  bool hasSpeed = false;
  bool hasLoopMode = false;
  bool hasShuffleEnabled = false;

  void onPlayerState(just_audio.PlayerState value) {
    playerState = value;
    hasPlayerState = true;
  }

  void onPosition(Duration value) {
    position = value;
    hasPosition = true;
  }

  void onBufferedPosition(Duration value) {
    bufferedPosition = value;
    hasBufferedPosition = true;
  }

  void onDuration(Duration? value) {
    duration = value;
    hasDuration = true;
  }

  void onCurrentIndex(int? value) {
    currentIndex = value;
    hasCurrentIndex = true;
  }

  void onSpeed(double value) {
    speed = value;
    hasSpeed = true;
  }

  void onLoopMode(just_audio.LoopMode value) {
    loopMode = value;
    hasLoopMode = true;
  }

  void onShuffleEnabled(bool value) {
    shuffleEnabled = value;
    hasShuffleEnabled = true;
  }
}
