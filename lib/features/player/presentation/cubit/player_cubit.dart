import 'package:flutter_bloc/flutter_bloc.dart';

enum PlayerPresentation { hidden, mini, expanded }

class PlayerState {
  const PlayerState({
    required this.presentation,
    required this.progress,
    required this.isPlaying,
    required this.speedIndex,
  });

  static const speeds = ['1.0x', '1.25x', '1.5x', '2.0x'];

  final PlayerPresentation presentation;
  final double progress;
  final bool isPlaying;
  final int speedIndex;

  String get speed => speeds[speedIndex];

  PlayerState copyWith({
    PlayerPresentation? presentation,
    double? progress,
    bool? isPlaying,
    int? speedIndex,
  }) => PlayerState(
    presentation: presentation ?? this.presentation,
    progress: progress ?? this.progress,
    isPlaying: isPlaying ?? this.isPlaying,
    speedIndex: speedIndex ?? this.speedIndex,
  );
}

class PlayerCubit extends Cubit<PlayerState> {
  PlayerCubit()
    : super(
        const PlayerState(
          presentation: PlayerPresentation.mini,
          progress: .45,
          isPlaying: true,
          speedIndex: 0,
        ),
      );

  void expand() =>
      emit(state.copyWith(presentation: PlayerPresentation.expanded));

  void minimize() =>
      emit(state.copyWith(presentation: PlayerPresentation.mini));

  void hide() => emit(state.copyWith(presentation: PlayerPresentation.hidden));

  void togglePlayback() => emit(state.copyWith(isPlaying: !state.isPlaying));

  void updateProgress(double value) =>
      emit(state.copyWith(progress: value.clamp(0.0, 1.0)));

  void seekBy(double offset) => updateProgress(state.progress + offset);

  void cycleSpeed() => emit(
    state.copyWith(
      speedIndex: (state.speedIndex + 1) % PlayerState.speeds.length,
    ),
  );
}
