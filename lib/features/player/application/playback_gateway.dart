import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

/// Public application boundary between player consumers and playback
/// infrastructure.
///
/// Invalid commands fail with a typed command failure without publishing a
/// speculative snapshot. Confirmed playback state and failures arrive through
/// [snapshots].
///
/// The gateway deliberately has no dependency on a concrete playback
/// implementation.
abstract interface class PlaybackGateway {
  Stream<PlaybackSnapshot> get snapshots;

  Future<void> loadQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> skipBy(Duration offset);
  Future<void> next();
  Future<void> previous();
  Future<void> setSpeed(double speed);
  Future<void> setRepeatMode(PlayerRepeatMode mode);
  Future<void> setShuffleEnabled(bool enabled);

  /// Retries the current recoverable playback failure atomically.
  Future<void> retry();
}
