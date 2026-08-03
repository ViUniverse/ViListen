import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/command_source.dart';

/// Internal command and snapshot port implemented by the playback handler.
///
/// The public application boundary is [PlaybackGateway]. This port carries
/// command provenance so UI and system callbacks can converge on the same
/// handler operations without sharing a zero-argument command API.
abstract interface class UiPlaybackCommandTarget {
  Stream<PlaybackSnapshot> get snapshots;

  Future<void> loadQueue(
    List<PlayerItem> items,
    int initialIndex,
    bool autoplay,
    CommandSource source,
  );

  Future<void> play(CommandSource source);
  Future<void> pause(CommandSource source);
  Future<void> stop(CommandSource source);
  Future<void> seek(Duration position, CommandSource source);
  Future<void> skipBy(Duration offset, CommandSource source);
  Future<void> next(CommandSource source);
  Future<void> previous(CommandSource source);
  Future<void> setSpeed(double speed, CommandSource source);
  Future<void> setRepeatMode(PlayerRepeatMode mode, CommandSource source);
  Future<void> setShuffleEnabled(bool enabled, CommandSource source);
  Future<void> retry(CommandSource source);
}
