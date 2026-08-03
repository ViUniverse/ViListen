import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ten_project_cua_ban/features/player/application/playback_gateway.dart';
import 'package:ten_project_cua_ban/features/player/application/player_command_policies.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';

/// Application Cubit that exposes confirmed playback snapshots to the UI.
final class PlayerCubit extends Cubit<PlayerState> {
  PlayerCubit(this._gateway)
    : super(PlayerState.fromSnapshot(PlaybackSnapshot.idle)) {
    _snapshotSubscription = _gateway.snapshots.distinct().listen(_emitSnapshot);
  }

  final PlaybackGateway _gateway;
  late final StreamSubscription<PlaybackSnapshot> _snapshotSubscription;
  bool? _pendingDesiredPlaying;
  int? _pendingIntentGeneration;
  int _nextIntentGeneration = 0;

  Future<void> play() => _gateway.play();

  Future<void> pause() => _gateway.pause();

  Future<void> stop() async {
    _reconcilePendingIntent();
    await _gateway.stop();
  }

  Future<void> seekTo(Duration position) => _gateway.seek(position);

  Future<void> skipBackward() =>
      _gateway.skipBy(-PlayerCommandPolicies.skipInterval);

  Future<void> skipForward() =>
      _gateway.skipBy(PlayerCommandPolicies.skipInterval);

  Future<void> togglePlayback() async {
    final desiredPlaying = !(_pendingDesiredPlaying ?? state.playing);
    final intentGeneration = ++_nextIntentGeneration;
    _pendingDesiredPlaying = desiredPlaying;
    _pendingIntentGeneration = intentGeneration;

    try {
      if (desiredPlaying) {
        await _gateway.play();
      } else {
        await _gateway.pause();
      }
    } catch (error, stackTrace) {
      if (_pendingIntentGeneration == intentGeneration) {
        _reconcilePendingIntent();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> open(PlayerItem item, {bool autoplay = true}) =>
      openQueue(<PlayerItem>[item], autoplay: autoplay);

  Future<void> openQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  }) =>
      _gateway.loadQueue(items, initialIndex: initialIndex, autoplay: autoplay);

  void _emitSnapshot(PlaybackSnapshot snapshot) {
    final pendingDesiredPlaying = _pendingDesiredPlaying;
    final confirmsPendingIntent =
        pendingDesiredPlaying != null &&
        (snapshot.playing == pendingDesiredPlaying || snapshot.failure != null);
    if (confirmsPendingIntent) {
      _reconcilePendingIntent();
    }
    final nextState = PlayerState.fromSnapshot(snapshot);
    if (nextState != state) {
      emit(nextState);
    }
  }

  void _reconcilePendingIntent() {
    _pendingDesiredPlaying = null;
    _pendingIntentGeneration = null;
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription.cancel();
    await super.close();
  }
}
