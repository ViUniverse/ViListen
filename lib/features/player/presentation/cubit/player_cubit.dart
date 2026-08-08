// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_bloc/flutter_bloc.dart';

// Migration-only legacy player types. Remove with PLR-110 after all player
// consumers migrate to the application layer.
enum LegacyPlayerPresentation { hidden, mini, expanded }

class LegacyPlayerState {
  const LegacyPlayerState({
    required this.presentation,
    required this.progress,
    required this.isPlaying,
    required this.speedIndex,
  });

  static const speeds = ['1.0x', '1.25x', '1.5x', '2.0x'];

  final LegacyPlayerPresentation presentation;
  final double progress;
  final bool isPlaying;
  final int speedIndex;

  String get speed => speeds[speedIndex];

  LegacyPlayerState copyWith({
    LegacyPlayerPresentation? presentation,
    double? progress,
    bool? isPlaying,
    int? speedIndex,
  }) => LegacyPlayerState(
    presentation: presentation ?? this.presentation,
    progress: progress ?? this.progress,
    isPlaying: isPlaying ?? this.isPlaying,
    speedIndex: speedIndex ?? this.speedIndex,
  );
}

class LegacyPlayerCubit extends Cubit<LegacyPlayerState> {
  LegacyPlayerCubit()
    : super(
        const LegacyPlayerState(
          presentation: LegacyPlayerPresentation.mini,
          progress: .45,
          isPlaying: true,
          speedIndex: 0,
        ),
      );

  void expand() =>
      emit(state.copyWith(presentation: LegacyPlayerPresentation.expanded));

  void minimize() =>
      emit(state.copyWith(presentation: LegacyPlayerPresentation.mini));

  void hide() =>
      emit(state.copyWith(presentation: LegacyPlayerPresentation.hidden));

  void togglePlayback() => emit(state.copyWith(isPlaying: !state.isPlaying));

  void updateProgress(double value) =>
      emit(state.copyWith(progress: value.clamp(0.0, 1.0)));

  void seekBy(double offset) => updateProgress(state.progress + offset);

  void cycleSpeed() => emit(
    state.copyWith(
      speedIndex: (state.speedIndex + 1) % LegacyPlayerState.speeds.length,
    ),
  );
}
