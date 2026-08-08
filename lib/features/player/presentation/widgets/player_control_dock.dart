// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart';

class PlayerControlDock extends StatelessWidget {
  const PlayerControlDock({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LegacyPlayerCubit, LegacyPlayerState>(
        buildWhen: (previous, current) =>
            previous.progress != current.progress ||
            previous.isPlaying != current.isPlaying ||
            previous.speedIndex != current.speedIndex,
        builder: (context, state) {
          final cubit = context.read<LegacyPlayerCubit>();
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
                      onChanged: cubit.updateProgress,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _timestamp(state.progress * 159),
                          style: _timeStyle,
                        ),
                        Text(
                          '-${_timestamp((1 - state.progress) * 159)}',
                          style: _timeStyle,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SmallControl(
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
                      ),
                      _SmallControl(
                        label: 'Tua lại 10 giây',
                        onPressed: () => cubit.seekBy(-10 / 159),
                        child: const Icon(Icons.replay_10_rounded, size: 28),
                      ),
                      Semantics(
                        button: true,
                        label: state.isPlaying ? 'Tạm dừng' : 'Phát',
                        child: InkResponse(
                          onTap: cubit.togglePlayback,
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
                              state.isPlaying
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
                        onPressed: () => cubit.seekBy(10 / 159),
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

String _timestamp(double seconds) {
  final value = seconds.round().clamp(0, 159);
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
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
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: IconButton(onPressed: onPressed, icon: child),
  );
}
