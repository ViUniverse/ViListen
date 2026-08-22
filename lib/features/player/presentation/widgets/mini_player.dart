// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, bool>(
        selector: (state) => state.currentItem != null,
        builder: (context, hasItem) => hasItem
            ? _MiniPlayerSurface(onOpen: onOpen)
            : const SizedBox.shrink(),
      );
}

typedef _MiniMetadata = ({String title, String artist, Duration? duration});

class _MiniPlayerSurface extends StatelessWidget {
  const _MiniPlayerSurface({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, String?>(
        selector: (state) => state.currentItem?.title,
        builder: (context, title) => Semantics(
          container: true,
          button: true,
          label: title == null ? 'Mở trình phát' : 'Mở trình phát $title',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                key: const ValueKey('mini-player'),
                height: 72,
                padding: const EdgeInsets.fromLTRB(13, 0, 12, 0),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xfff2542c), Color(0xffec4899)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x19000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .95),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Row(
                    children: [
                      const _MiniArtwork(),
                      const SizedBox(width: 12),
                      const Expanded(child: _MiniMetadataView()),
                      const _MiniPlaybackAction(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, String?>(
        selector: (state) => state.currentItem?.title,
        builder: (context, title) => Semantics(
          container: true,
          image: true,
          label: title == null ? 'Ảnh bìa' : 'Ảnh bìa $title',
          child: const PlayerArtworkHero(size: 44, radius: 16),
        ),
      );
}

class _MiniMetadataView extends StatelessWidget {
  const _MiniMetadataView();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _MiniMetadata?>(
        selector: (state) {
          final item = state.currentItem;
          if (item == null) {
            return null;
          }

          return (
            title: item.title,
            artist: item.artist,
            duration: state.duration > Duration.zero
                ? state.duration
                : item.duration,
          );
        },
        builder: (context, metadata) {
          if (metadata == null) {
            return const SizedBox.shrink();
          }

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metadata.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${metadata.artist} • ${_formatDuration(metadata.duration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xff64748b),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
              const _MiniProgress(),
            ],
          );
        },
      );
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, double>(
        selector: (state) => state.progress,
        builder: (context, progress) => ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            color: const Color(0xfff2542c),
            backgroundColor: const Color(0xffe2e8f0),
          ),
        ),
      );
}

typedef _MiniPlayback = ({bool playing, bool buffering});

class _MiniPlaybackAction extends StatelessWidget {
  const _MiniPlaybackAction();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _MiniPlayback>(
        selector: (state) =>
            (playing: state.playing, buffering: state.isBuffering),
        builder: (context, playback) {
          final cubit = context.read<PlayerCubit>();
          return IconButton(
            tooltip: playback.playing ? 'Tạm dừng' : 'Phát',
            onPressed: cubit.togglePlayback,
            icon: Stack(
              alignment: Alignment.center,
              children: [
                if (playback.buffering)
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xfff2542c),
                    ),
                  ),
                Icon(
                  playback.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: const Color(0xfff2542c),
                  size: 29,
                ),
              ],
            ),
          );
        },
      );
}

String _formatDuration(Duration? duration) {
  if (duration == null || duration <= Duration.zero) {
    return '—';
  }

  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;

  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}
