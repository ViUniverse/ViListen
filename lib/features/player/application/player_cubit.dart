import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ten_project_cua_ban/features/player/application/playback_gateway.dart';
import 'package:ten_project_cua_ban/features/player/application/player_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';

/// Application Cubit that exposes confirmed playback snapshots to the UI.
final class PlayerCubit extends Cubit<PlayerState> {
  PlayerCubit(this._gateway)
    : super(PlayerState.fromSnapshot(PlaybackSnapshot.idle)) {
    _snapshotSubscription = _gateway.snapshots.distinct().listen(_emitSnapshot);
  }

  final PlaybackGateway _gateway;
  late final StreamSubscription<PlaybackSnapshot> _snapshotSubscription;

  void _emitSnapshot(PlaybackSnapshot snapshot) {
    final nextState = PlayerState.fromSnapshot(snapshot);
    if (nextState != state) {
      emit(nextState);
    }
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription.cancel();
    await super.close();
  }
}
