// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_command_policies.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/presentation/player_duration_formatter.dart';

class PlayerControlDock extends StatelessWidget {
  const PlayerControlDock({super.key});

  @override
  Widget build(BuildContext context) => Container(
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
      child: const Column(
        children: [
          _DockTimeline(),
          _DockPrimaryControls(),
          SizedBox(height: 4),
          _DockOptionControls(),
        ],
      ),
    ),
  );
}

typedef _TimelineSlice = ({
  String? itemId,
  Duration position,
  Duration bufferedPosition,
  Duration duration,
});

class _DockTimeline extends StatefulWidget {
  const _DockTimeline();

  @override
  State<_DockTimeline> createState() => _DockTimelineState();
}

class _DockTimelineState extends State<_DockTimeline> {
  final _viewKey = GlobalKey<_DockTimelineViewState>();

  @override
  Widget build(BuildContext context) => BlocListener<PlayerCubit, PlayerState>(
    listenWhen: (previous, current) =>
        _viewKey.currentState?._isDragging == true &&
        (current.duration <= Duration.zero ||
            previous.currentItem?.id != current.currentItem?.id),
    listener: (context, state) => _viewKey.currentState?._clearSeekPreview(),
    child: BlocSelector<PlayerCubit, PlayerState, _TimelineSlice>(
      selector: (state) => (
        itemId: state.currentItem?.id,
        position: state.position,
        bufferedPosition: state.playback.bufferedPosition,
        duration: state.duration,
      ),
      builder: (context, timeline) =>
          _DockTimelineView(key: _viewKey, timeline: timeline),
    ),
  );
}

class _DockTimelineView extends StatefulWidget {
  const _DockTimelineView({super.key, required this.timeline});

  final _TimelineSlice timeline;

  @override
  State<_DockTimelineView> createState() => _DockTimelineViewState();
}

class _DockTimelineViewState extends State<_DockTimelineView> {
  bool _isDragging = false;
  Duration? _previewPosition;
  String? _dragItemId;

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

  void _updateSeekPreview(double value) {
    final duration = widget.timeline.duration;
    if (!_isDragging || duration <= Duration.zero) {
      return;
    }

    setState(() {
      _previewPosition = _positionForProgress(value, duration);
    });
  }

  void _commitSeek(double value) {
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

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    final canSeek = timeline.duration > Duration.zero;
    final bufferedProgress = _bufferedProgress(
      timeline.bufferedPosition,
      timeline.duration,
    );
    final hasActivePreview =
        _isDragging &&
        _previewPosition != null &&
        timeline.itemId == _dragItemId &&
        canSeek;
    final displayedPosition = hasActivePreview
        ? _previewPosition!
        : timeline.position;
    final displayedProgress = _progressForPosition(
      displayedPosition,
      timeline.duration,
    );
    final displayedRemaining = _remainingForPosition(
      displayedPosition,
      timeline.duration,
    );

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: const Color(0xfff2542c),
            inactiveTrackColor: const Color(0xffe2e8f0),
          ),
          child: Slider(
            value: displayedProgress,
            secondaryTrackValue: bufferedProgress,
            onChangeStart: canSeek ? _startSeekPreview : null,
            onChanged: canSeek ? _updateSeekPreview : null,
            onChangeEnd: canSeek ? _commitSeek : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatElapsed(displayedPosition), style: _timeStyle),
              Text(formatRemaining(displayedRemaining), style: _timeStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _DockPrimaryControls extends StatelessWidget {
  const _DockPrimaryControls();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: const [
      _PreviousControl(),
      _SkipBackwardControl(),
      _PlaybackAction(),
      _SkipForwardControl(),
      _NextControl(),
    ],
  );
}

class _PreviousControl extends StatelessWidget {
  const _PreviousControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, bool>(
        selector: _canGoPrevious,
        builder: (context, enabled) => _SmallControl(
          label: 'Bài trước',
          onPressed: enabled ? context.read<PlayerCubit>().previous : null,
          child: const Icon(Icons.skip_previous_rounded, size: 28),
        ),
      );
}

class _SkipBackwardControl extends StatelessWidget {
  const _SkipBackwardControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, bool>(
        selector: (state) => state.duration > Duration.zero,
        builder: (context, enabled) => _SmallControl(
          label: 'Tua lại 10 giây',
          onPressed: enabled ? context.read<PlayerCubit>().skipBackward : null,
          child: const Icon(Icons.replay_10_rounded, size: 28),
        ),
      );
}

typedef _PlaybackSlice = ({bool completed, bool playing});

class _PlaybackAction extends StatelessWidget {
  const _PlaybackAction();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _PlaybackSlice>(
        selector: (state) =>
            (completed: state.isCompleted, playing: state.playing),
        builder: (context, playback) {
          final cubit = context.read<PlayerCubit>();
          return Semantics(
            button: true,
            label: playback.completed
                ? 'Phát lại'
                : playback.playing
                ? 'Tạm dừng'
                : 'Phát',
            child: InkResponse(
              onTap: playback.completed ? cubit.play : cubit.togglePlayback,
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
                  playback.completed
                      ? Icons.replay_rounded
                      : playback.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 37,
                ),
              ),
            ),
          );
        },
      );
}

class _SkipForwardControl extends StatelessWidget {
  const _SkipForwardControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, bool>(
        selector: (state) => state.duration > Duration.zero,
        builder: (context, enabled) => _SmallControl(
          label: 'Tua tới 10 giây',
          onPressed: enabled ? context.read<PlayerCubit>().skipForward : null,
          child: const Icon(Icons.forward_10_rounded, size: 28),
        ),
      );
}

class _NextControl extends StatelessWidget {
  const _NextControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, bool>(
        selector: _canGoNext,
        builder: (context, enabled) => _SmallControl(
          label: 'Bài tiếp theo',
          onPressed: enabled ? context.read<PlayerCubit>().next : null,
          child: const Icon(Icons.skip_next_rounded, size: 28),
        ),
      );
}

class _DockOptionControls extends StatelessWidget {
  const _DockOptionControls();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: const [_SpeedControl(), _RepeatControl(), _ShuffleControl()],
  );
}

typedef _SpeedSlice = ({double speed, bool enabled});

class _SpeedControl extends StatelessWidget {
  const _SpeedControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _SpeedSlice>(
        selector: (state) =>
            (speed: state.playback.speed, enabled: _controlsAvailable(state)),
        builder: (context, slice) {
          final cubit = context.read<PlayerCubit>();
          return _SmallControl(
            label: 'Tốc độ phát ${_formatSpeed(slice.speed)}',
            onPressed: slice.enabled
                ? () => cubit.setSpeed(_nextSpeedPreset(slice.speed))
                : null,
            child: Text(
              _formatSpeed(slice.speed),
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

typedef _RepeatSlice = ({PlayerRepeatMode mode, bool enabled});

class _RepeatControl extends StatelessWidget {
  const _RepeatControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _RepeatSlice>(
        selector: (state) => (
          mode: state.playback.repeatMode,
          enabled: _controlsAvailable(state),
        ),
        builder: (context, slice) {
          final cubit = context.read<PlayerCubit>();
          return _SmallControl(
            label: _repeatLabel(slice.mode),
            onPressed: slice.enabled ? cubit.cycleRepeatMode : null,
            child: Icon(
              _repeatIcon(slice.mode),
              color: _optionColor(slice.mode != PlayerRepeatMode.off),
              size: 25,
            ),
          );
        },
      );
}

typedef _ShuffleSlice = ({bool enabled, bool available});

class _ShuffleControl extends StatelessWidget {
  const _ShuffleControl();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _ShuffleSlice>(
        selector: (state) => (
          enabled: state.playback.shuffleEnabled,
          available: _controlsAvailable(state),
        ),
        builder: (context, slice) {
          final cubit = context.read<PlayerCubit>();
          return _SmallControl(
            label: slice.enabled ? 'Trộn bài: bật' : 'Trộn bài: tắt',
            onPressed: slice.available ? cubit.toggleShuffle : null,
            child: Icon(
              Icons.shuffle_rounded,
              color: _optionColor(slice.enabled),
              size: 25,
            ),
          );
        },
      );
}

bool _controlsAvailable(PlayerState state) {
  final snapshot = state.playback;
  final currentIndex = snapshot.currentIndex;
  final hasValidQueueContext =
      state.currentItem != null &&
      currentIndex != null &&
      currentIndex >= 0 &&
      currentIndex < snapshot.queue.length;
  return hasValidQueueContext &&
      snapshot.failure == null &&
      snapshot.processingState != PlaybackProcessingState.idle &&
      snapshot.processingState != PlaybackProcessingState.error;
}

bool _canGoNext(PlayerState state) {
  final snapshot = state.playback;
  return _controlsAvailable(state) &&
      (snapshot.hasNext ||
          snapshot.repeatMode == PlayerRepeatMode.all &&
              snapshot.queue.length > 1);
}

bool _canGoPrevious(PlayerState state) {
  final snapshot = state.playback;
  return _controlsAvailable(state) &&
      (snapshot.hasPrevious ||
          state.position > PlayerCommandPolicies.previousRestartThreshold ||
          snapshot.repeatMode == PlayerRepeatMode.all &&
              snapshot.queue.length > 1);
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

double _nextSpeedPreset(double current) {
  for (final preset in PlayerCommandPolicies.speedPresets) {
    if (preset > current) {
      return preset;
    }
  }

  return PlayerCommandPolicies.speedPresets.first;
}

String _formatSpeed(double speed) {
  final fixed = speed.toStringAsFixed(2);
  final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
  final normalized = trimmed.endsWith('.') ? '${trimmed}0' : trimmed;
  return '${normalized}x';
}

String _repeatLabel(PlayerRepeatMode mode) => switch (mode) {
  PlayerRepeatMode.off => 'Lặp lại: tắt',
  PlayerRepeatMode.one => 'Lặp lại: một',
  PlayerRepeatMode.all => 'Lặp lại: tất cả',
};

IconData _repeatIcon(PlayerRepeatMode mode) => switch (mode) {
  PlayerRepeatMode.off || PlayerRepeatMode.all => Icons.repeat_rounded,
  PlayerRepeatMode.one => Icons.repeat_one_rounded,
};

Color _optionColor(bool active) =>
    active ? const Color(0xfff2542c) : const Color(0xff94a3b8);

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
