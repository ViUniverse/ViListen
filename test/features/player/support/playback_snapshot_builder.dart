// SPDX-License-Identifier: Apache-2.0

import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

PlaybackSnapshot buildPlaybackSnapshot({
  PlayerItem? currentItem,
  List<PlayerItem> queue = const <PlayerItem>[],
  int? currentIndex,
  PlaybackProcessingState processingState = PlaybackProcessingState.idle,
  bool playing = false,
  Duration position = Duration.zero,
  Duration bufferedPosition = Duration.zero,
  Duration duration = Duration.zero,
  double speed = 1.0,
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off,
  bool shuffleEnabled = false,
  PlayerFailure? failure,
}) => PlaybackSnapshot(
  currentItem: currentItem,
  queue: queue,
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
