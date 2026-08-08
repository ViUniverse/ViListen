// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';

void main() {
  test('defines playback processing states in domain order', () {
    expect(PlaybackProcessingState.values, [
      PlaybackProcessingState.idle,
      PlaybackProcessingState.loading,
      PlaybackProcessingState.buffering,
      PlaybackProcessingState.ready,
      PlaybackProcessingState.completed,
      PlaybackProcessingState.error,
    ]);
  });

  test('defines repeat modes in cycle order', () {
    expect(PlayerRepeatMode.values, [
      PlayerRepeatMode.off,
      PlayerRepeatMode.one,
      PlayerRepeatMode.all,
    ]);
  });
}
