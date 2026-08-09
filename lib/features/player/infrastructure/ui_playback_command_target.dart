// SPDX-License-Identifier: Apache-2.0

import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';

/// Internal command and snapshot port implemented by the playback handler.
///
/// The public application boundary is [PlaybackGateway]. This port carries
/// command provenance so UI and system callbacks can converge on the same
/// handler operations without colliding with [BaseAudioHandler] method names.
abstract interface class UiPlaybackCommandTarget {
  Stream<PlaybackSnapshot> get snapshots;

  Future<void> handleLoadQueue(
    List<PlayerItem> items,
    int initialIndex,
    bool autoplay,
    CommandSource source,
  );

  Future<void> handlePlay(CommandSource source);
  Future<void> handlePause(CommandSource source);
  Future<void> handleStop(CommandSource source);
  Future<void> handleSeek(Duration position, CommandSource source);
  Future<void> handleSkipBy(Duration offset, CommandSource source);
  Future<void> handleNext(CommandSource source);
  Future<void> handlePrevious(CommandSource source);
  Future<void> handleSetSpeed(double speed, CommandSource source);
  Future<void> handleSetRepeatMode(PlayerRepeatMode mode, CommandSource source);
  Future<void> handleSetShuffleEnabled(bool enabled, CommandSource source);
  Future<void> handleRetry(CommandSource source);
}
