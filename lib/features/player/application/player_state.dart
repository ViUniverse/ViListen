import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';

/// UI projection of one confirmed playback snapshot.
final class PlayerState {
  const PlayerState({required this.playback});

  factory PlayerState.fromSnapshot(PlaybackSnapshot snapshot) =>
      PlayerState(playback: snapshot);

  final PlaybackSnapshot playback;

  PlayerItem? get currentItem => playback.currentItem;

  bool get playing => playback.playing;

  bool get isBuffering => playback.isBuffering;

  bool get isCompleted => playback.isCompleted;

  double get progress => playback.progress;

  Duration get position => playback.position;

  Duration get duration => playback.duration;

  PlayerFailure? get failure => playback.failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerState && other.playback == playback;

  @override
  int get hashCode => playback.hashCode;
}
