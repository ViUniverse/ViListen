// SPDX-License-Identifier: Apache-2.0

import 'package:ten_project_cua_ban/features/player/application/playback_gateway.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/command_source.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/ui_playback_command_target.dart';

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
  }) => _target.loadQueue(items, initialIndex, autoplay, CommandSource.ui);

  @override
  Future<void> play() => _target.play(CommandSource.ui);

  @override
  Future<void> pause() => _target.pause(CommandSource.ui);

  @override
  Future<void> stop() => _target.stop(CommandSource.ui);

  @override
  Future<void> seek(Duration position) =>
      _target.seek(position, CommandSource.ui);

  @override
  Future<void> skipBy(Duration offset) =>
      _target.skipBy(offset, CommandSource.ui);

  @override
  Future<void> next() => _target.next(CommandSource.ui);

  @override
  Future<void> previous() => _target.previous(CommandSource.ui);

  @override
  Future<void> setSpeed(double speed) =>
      _target.setSpeed(speed, CommandSource.ui);

  @override
  Future<void> setRepeatMode(PlayerRepeatMode mode) =>
      _target.setRepeatMode(mode, CommandSource.ui);

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      _target.setShuffleEnabled(enabled, CommandSource.ui);

  @override
  Future<void> retry() => _target.retry(CommandSource.ui);
}
