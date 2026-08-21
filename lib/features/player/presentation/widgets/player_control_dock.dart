// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import 'package:vi_listen/features/player/presentation/player_duration_formatter.dart';

class PlayerControlDock extends StatefulWidget {
  const PlayerControlDock({super.key});

  @override
  State<PlayerControlDock> createState() => _PlayerControlDockState();
}

class _PlayerControlDockState extends State<PlayerControlDock> {
  bool _isDragging = false;
  Duration? _previewPosition;
  String? _dragItemId;

  @override
  Widget build(BuildContext context) => BlocConsumer<PlayerCubit, PlayerState>(
    listenWhen: (previous, current) {
      if (!_isDragging) {
        return false;
      }

      return current.duration <= Duration.zero ||
          previous.currentItem?.id != current.currentItem?.id;
    },
    listener: (context, state) => _clearSeekPreview(),
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
      final hasActivePreview =
          _isDragging &&
          _previewPosition != null &&
          state.currentItem?.id == _dragItemId &&
          canSeek;
      final displayedPosition = hasActivePreview
          ? _previewPosition!
          : state.position;
      final displayedProgress = _progressForPosition(
        displayedPosition,
        duration,
      );
      final displayedRemaining = _remainingForPosition(
        displayedPosition,
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
                  value: displayedProgress,
                  secondaryTrackValue: bufferedProgress,
                  onChangeStart: canSeek ? _startSeekPreview : null,
                  onChanged: canSeek
                      ? (value) => _updateSeekPreview(value, duration)
                      : null,
                  onChangeEnd: canSeek
                      ? (value) => _commitSeek(context, value)
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatElapsed(displayedPosition), style: _timeStyle),
                    Text(
                      formatRemaining(displayedRemaining),
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

  void _startSeekPreview(double _) {
    final state = context.read<PlayerCubit>().state;
    if (state.duration <= Duration.zero) {
      return;
    }

    setState(() {
      _isDragging = true;
      _dragItemId = state.currentItem?.id;
      _previewPosition = null;
    });
  }

  void _updateSeekPreview(double value, Duration duration) {
    if (!_isDragging || duration <= Duration.zero) {
      return;
    }

    setState(() {
      _previewPosition = _positionForProgress(value, duration);
    });
  }

  void _commitSeek(BuildContext context, double value) {
    final cubit = context.read<PlayerCubit>();
    final state = cubit.state;
    final itemId = state.currentItem?.id;
    if (!_isDragging ||
        state.duration <= Duration.zero ||
        itemId != _dragItemId) {
      _clearSeekPreview();
      return;
    }

    final target = _positionForProgress(value, state.duration);
    _clearSeekPreview();
    unawaited(cubit.seekTo(target));
  }

  void _clearSeekPreview() {
    if (!_isDragging && _previewPosition == null && _dragItemId == null) {
      return;
    }

    setState(() {
      _isDragging = false;
      _previewPosition = null;
      _dragItemId = null;
    });
  }
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

double _progressForPosition(Duration position, Duration duration) {
  final durationMicros = duration.inMicroseconds;
  if (durationMicros <= 0) {
    return 0.0;
  }

  return (position.inMicroseconds / durationMicros).clamp(0.0, 1.0).toDouble();
}

Duration _remainingForPosition(Duration position, Duration duration) {
  if (duration <= Duration.zero) {
    return Duration.zero;
  }

  final boundedPosition = position <= Duration.zero
      ? Duration.zero
      : position >= duration
      ? duration
      : position;
  return duration - boundedPosition;
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
