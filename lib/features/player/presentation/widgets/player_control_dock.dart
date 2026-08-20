// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import 'package:vi_listen/features/player/presentation/player_duration_formatter.dart';

class PlayerControlDock extends StatelessWidget {
  const PlayerControlDock({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (previous, current) =>
        previous.position != current.position ||
        previous.duration != current.duration ||
        previous.playback.bufferedPosition !=
            current.playback.bufferedPosition ||
        previous.playing != current.playing ||
        previous.isCompleted != current.isCompleted,
    builder: (context, state) {
      final cubit = context.read<PlayerCubit>();
      final duration = state.duration;
      final canSeek = duration > Duration.zero;
      final bufferedProgress = _bufferedProgress(
        state.playback.bufferedPosition,
        duration,
      );
      return Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x4df2542c), Color(0x4dec4899)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x161f2687),
              blurRadius: 28,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(19, 17, 19, 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .95),
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: const Color(0xfff2542c),
                  inactiveTrackColor: const Color(0xffe2e8f0),
                ),
                child: Slider(
                  value: state.progress,
                  secondaryTrackValue: bufferedProgress,
                  // PLR-106 will replace this direct seek with local preview
                  // and a single seek commit.
                  onChanged: canSeek
                      ? (value) =>
                            cubit.seekTo(_positionForProgress(value, duration))
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatElapsed(state.position), style: _timeStyle),
                    Text(
                      formatRemaining(state.playback.remaining),
                      style: _timeStyle,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _LegacySpeedControl(),
                  _SmallControl(
                    label: 'Tua lại 10 giây',
                    onPressed: canSeek ? cubit.skipBackward : null,
                    child: const Icon(Icons.replay_10_rounded, size: 28),
                  ),
                  Semantics(
                    button: true,
                    label: state.isCompleted
                        ? 'Phát lại'
                        : state.playing
                        ? 'Tạm dừng'
                        : 'Phát',
                    child: InkResponse(
                      onTap: state.isCompleted
                          ? cubit.play
                          : cubit.togglePlayback,
                      radius: 38,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xfff2542c), Color(0xffec4899)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x66f2542c),
                              blurRadius: 18,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          state.isCompleted
                              ? Icons.replay_rounded
                              : state.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 37,
                        ),
                      ),
                    ),
                  ),
                  _SmallControl(
                    label: 'Tua tới 10 giây',
                    onPressed: canSeek ? cubit.skipForward : null,
                    child: const Icon(Icons.forward_10_rounded, size: 28),
                  ),
                  _SmallControl(
                    label: 'Lặp lại',
                    onPressed: () {},
                    child: const Icon(
                      Icons.repeat_rounded,
                      color: Color(0xff94a3b8),
                      size: 25,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

double? _bufferedProgress(Duration bufferedPosition, Duration duration) {
  final durationMicros = duration.inMicroseconds;
  if (durationMicros <= 0) {
    return null;
  }

  return (bufferedPosition.inMicroseconds / durationMicros)
      .clamp(0.0, 1.0)
      .toDouble();
}

Duration _positionForProgress(double progress, Duration duration) {
  final boundedProgress = progress.clamp(0.0, 1.0).toDouble();
  return Duration(
    microseconds: (duration.inMicroseconds * boundedProgress).round(),
  );
}

const _timeStyle = TextStyle(
  color: Color(0xff64748b),
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

class _SmallControl extends StatelessWidget {
  const _SmallControl({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: IconButton(onPressed: onPressed, icon: child),
  );
}

class _LegacySpeedControl extends StatelessWidget {
  const _LegacySpeedControl();

  @override
  Widget build(BuildContext context) =>
      // TODO(PLR-111): Migrate speed/options controls to PlayerCubit.
      BlocBuilder<
        legacy_player.LegacyPlayerCubit,
        legacy_player.LegacyPlayerState
      >(
        buildWhen: (previous, current) =>
            previous.speedIndex != current.speedIndex,
        builder: (context, state) {
          final cubit = context.read<legacy_player.LegacyPlayerCubit>();
          return _SmallControl(
            label: 'Tốc độ phát ${state.speed}',
            onPressed: cubit.cycleSpeed,
            child: Text(
              state.speed,
              style: const TextStyle(
                color: Color(0xff64748b),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          );
        },
      );
}
