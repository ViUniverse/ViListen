// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/playback_gateway.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

void main() {
  test('a compile-time fake can implement the complete gateway contract', () {
    final PlaybackGateway gateway = _CompileTimePlaybackGateway();

    expect(gateway, isA<PlaybackGateway>());
  });
}

final class _CompileTimePlaybackGateway implements PlaybackGateway {
  @override
  Stream<PlaybackSnapshot> get snapshots =>
      const Stream<PlaybackSnapshot>.empty();

  @override
  Future<void> loadQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipBy(Duration offset) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setRepeatMode(PlayerRepeatMode mode) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> retry() async {}
}
