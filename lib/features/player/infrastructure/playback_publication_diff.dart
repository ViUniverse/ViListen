// SPDX-License-Identifier: Apache-2.0

import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/infrastructure/player_item_mapper.dart';
import 'package:vi_listen/features/player/infrastructure/system_playback_state_mapper.dart';

/// Classifies which outward playback publications differ between snapshots.
///
/// This class only compares values. It does not decide publication cadence,
/// retain event causes, or perform platform/UI side effects.
final class PlaybackPublicationDiff {
  const PlaybackPublicationDiff._({
    required this.snapshotChanged,
    required this.playbackStateChanged,
    required this.mediaItemChanged,
    required this.queueChanged,
  });

  static final _comparisonTime = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  static final _comparisonMapper = SystemPlaybackStateMapper(
    // The mapped PlaybackState is used only for value comparison. It must not
    // be published; real publication must use the production clock.
    now: () => _comparisonTime,
  );

  /// Compares the latest accepted reduced snapshot with [current].
  factory PlaybackPublicationDiff.between({
    required PlaybackSnapshot previous,
    required PlaybackSnapshot current,
  }) {
    // Short-circuit before mapping or walking the queue for duplicates.
    if (previous == current) {
      return const PlaybackPublicationDiff._(
        snapshotChanged: false,
        playbackStateChanged: false,
        mediaItemChanged: false,
        queueChanged: false,
      );
    }

    return PlaybackPublicationDiff._(
      snapshotChanged: true,
      playbackStateChanged: !_playbackStateEquals(previous, current),
      mediaItemChanged: !_mediaItemProjectionEquals(
        previous.currentItem,
        current.currentItem,
      ),
      queueChanged: !_queueProjectionEquals(previous.queue, current.queue),
    );
  }

  /// Whether the domain should receive the current snapshot.
  final bool snapshotChanged;

  /// Whether the OS playback-state payload differs.
  final bool playbackStateChanged;

  /// Whether the current OS media-item payload differs.
  final bool mediaItemChanged;

  /// Whether the OS queue payload differs, including order.
  final bool queueChanged;

  bool get isDuplicate => !snapshotChanged;

  static bool _playbackStateEquals(
    PlaybackSnapshot first,
    PlaybackSnapshot second,
  ) => _comparisonMapper.map(first) == _comparisonMapper.map(second);

  /// Compares the payload produced by [PlayerItemMapper], not PlayerItem's
  /// full domain value. Domain-only complex extras are not platform payload.
  static bool _mediaItemProjectionEquals(
    PlayerItem? first,
    PlayerItem? second,
  ) {
    if (identical(first, second)) {
      return true;
    }
    if (first == null || second == null) {
      return false;
    }

    final firstMediaItem = PlayerItemMapper.toMediaItem(first);
    final secondMediaItem = PlayerItemMapper.toMediaItem(second);

    return firstMediaItem.id == secondMediaItem.id &&
        firstMediaItem.title == secondMediaItem.title &&
        firstMediaItem.artist == secondMediaItem.artist &&
        firstMediaItem.album == secondMediaItem.album &&
        firstMediaItem.artUri == secondMediaItem.artUri &&
        firstMediaItem.duration == secondMediaItem.duration &&
        _mapEquals(firstMediaItem.extras, secondMediaItem.extras);
  }

  static bool _queueProjectionEquals(
    List<PlayerItem> first,
    List<PlayerItem> second,
  ) {
    if (identical(first, second)) {
      return true;
    }
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (!_mediaItemProjectionEquals(first[index], second[index])) {
        return false;
      }
    }
    return true;
  }

  static bool _mapEquals(
    Map<String, dynamic>? first,
    Map<String, dynamic>? second,
  ) {
    if (identical(first, second)) {
      return true;
    }
    if (first == null || second == null || first.length != second.length) {
      return false;
    }

    for (final entry in first.entries) {
      if (!second.containsKey(entry.key) || second[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
