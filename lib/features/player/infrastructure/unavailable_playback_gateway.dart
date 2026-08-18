// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:vi_listen/features/player/application/playback_gateway.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';

/// A playback boundary used when audio bootstrap cannot create a handler.
///
/// This gateway deliberately owns no handler, engine, player, or platform
/// resource. It gives every subscriber the same unavailable snapshot and
/// rejects every command with a stable typed failure.
final class UnavailablePlaybackGateway implements PlaybackGateway {
  static final PlaybackSnapshot _unavailableSnapshot = PlaybackSnapshot(
    currentItem: null,
    queue: const <PlayerItem>[],
    currentIndex: null,
    processingState: PlaybackProcessingState.error,
    playing: false,
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: Duration.zero,
    speed: 1.0,
    repeatMode: PlayerRepeatMode.off,
    shuffleEnabled: false,
    failure: const PlayerFailure(
      code: 'bootstrapUnavailable',
      message: 'Audio service is unavailable.',
      isRecoverable: false,
    ),
  );

  @override
  Stream<PlaybackSnapshot> get snapshots =>
      Stream<PlaybackSnapshot>.multi((subscriber) {
        scheduleMicrotask(() {
          if (subscriber.isClosed) {
            return;
          }
          subscriber.addSync(_unavailableSnapshot);
          subscriber.close();
        });
      }, isBroadcast: true);

  @override
  Future<void> loadQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  }) => _unavailable('loadQueue');

  @override
  Future<void> play() => _unavailable('play');

  @override
  Future<void> pause() => _unavailable('pause');

  @override
  Future<void> stop() => _unavailable('stop');

  @override
  Future<void> seek(Duration position) => _unavailable('seek');

  @override
  Future<void> skipBy(Duration offset) => _unavailable('skipBy');

  @override
  Future<void> next() => _unavailable('next');

  @override
  Future<void> previous() => _unavailable('previous');

  @override
  Future<void> setSpeed(double speed) => _unavailable('setSpeed');

  @override
  Future<void> setRepeatMode(PlayerRepeatMode mode) =>
      _unavailable('setRepeatMode');

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      _unavailable('setShuffleEnabled');

  @override
  Future<void> retry() => _unavailable('retry');

  Future<void> _unavailable(String command) => Future<void>.error(
    PlayerCommandFailure(
      code: 'commandUnavailable',
      message: 'Playback command is unavailable.',
      command: command,
    ),
  );
}
