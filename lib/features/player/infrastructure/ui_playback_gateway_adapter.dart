// SPDX-License-Identifier: Apache-2.0

import 'package:vi_listen/features/player/application/playback_gateway.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_command_target.dart';

/// Adapts the application playback boundary to the internal UI command port.
final class UiPlaybackGatewayAdapter implements PlaybackGateway {
  UiPlaybackGatewayAdapter(this._target);

  final UiPlaybackCommandTarget _target;

  @override
  Stream<PlaybackSnapshot> get snapshots => _target.snapshots;

  @override
  Future<void> loadQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  }) =>
      _target.handleLoadQueue(items, initialIndex, autoplay, CommandSource.ui);

  @override
  Future<void> play() => _target.handlePlay(CommandSource.ui);

  @override
  Future<void> pause() => _target.handlePause(CommandSource.ui);

  @override
  Future<void> stop() => _target.handleStop(CommandSource.ui);

  @override
  Future<void> seek(Duration position) =>
      _target.handleSeek(position, CommandSource.ui);

  @override
  Future<void> skipBy(Duration offset) =>
      _target.handleSkipBy(offset, CommandSource.ui);

  @override
  Future<void> next() => _target.handleNext(CommandSource.ui);

  @override
  Future<void> previous() => _target.handlePrevious(CommandSource.ui);

  @override
  Future<void> setSpeed(double speed) =>
      _target.handleSetSpeed(speed, CommandSource.ui);

  @override
  Future<void> setRepeatMode(PlayerRepeatMode mode) =>
      _target.handleSetRepeatMode(mode, CommandSource.ui);

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      _target.handleSetShuffleEnabled(enabled, CommandSource.ui);

  @override
  Future<void> retry() => _target.handleRetry(CommandSource.ui);
}
