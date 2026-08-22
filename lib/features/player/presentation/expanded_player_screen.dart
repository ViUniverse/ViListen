// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_artwork.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_control_dock.dart';

class ExpandedPlayerRoute extends PageRouteBuilder<void> {
  ExpandedPlayerRoute()
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ExpandedPlayerScreen(),
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
          return AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              if (animation.status == AnimationStatus.reverse) {
                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                  child: child,
                );
              }
              return SlideTransition(position: slide, child: child);
            },
          );
        },
      );
}

class ExpandedPlayerScreen extends StatefulWidget {
  const ExpandedPlayerScreen({super.key});

  @override
  State<ExpandedPlayerScreen> createState() => _ExpandedPlayerScreenState();
}

class _ExpandedPlayerScreenState extends State<ExpandedPlayerScreen> {
  static const _minSheetSize = .2;
  final _sheetController = DraggableScrollableController();
  double _sheetExtent = _minSheetSize;
  double _dismissFraction = 0;
  bool _isDismissingGesture = false;
  bool _autoPopRequested = false;
  bool _initialPlaybackCheckScheduled = false;

  bool get _showBottomPlayer => _sheetExtent >= .96;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialPlaybackCheckScheduled) {
      return;
    }

    _initialPlaybackCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (context.read<PlayerCubit>().state.currentItem == null) {
        _tryAutoPop();
      }
    });
  }

  void _tryAutoPop() {
    if (!mounted || _autoPopRequested) {
      return;
    }

    final route = ModalRoute.of(context);
    if (route is! ExpandedPlayerRoute || !route.isCurrent) {
      return;
    }

    _autoPopRequested = true;
    Navigator.of(context).pop();
  }

  void _dragSheet(DragUpdateDetails details) {
    final nextSize =
        (_sheetController.size -
                details.delta.dy / MediaQuery.sizeOf(context).height)
            .clamp(_minSheetSize, 1.0);
    _sheetController.jumpTo(nextSize);
  }

  void _settleSheet(DragEndDetails details) {
    _sheetController.animateTo(
      _sheetController.size >= .6 ? 1 : _minSheetSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _dragToMinimize(DragUpdateDetails details) {
    final delta = details.delta.dy / MediaQuery.sizeOf(context).height;
    if (delta <= 0 && _dismissFraction == 0) return;

    setState(() {
      _isDismissingGesture = true;
      _dismissFraction = (_dismissFraction + delta).clamp(0.0, 1.0);
    });
  }

  void _settleMinimize(DragEndDetails details) {
    final shouldClose =
        _dismissFraction >= .18 || details.velocity.pixelsPerSecond.dy >= 850;
    if (shouldClose) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isDismissingGesture = false;
      _dismissFraction = 0;
    });
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<PlayerCubit, PlayerState>(
    listenWhen: (previous, current) =>
        previous.currentItem != null && current.currentItem == null,
    listener: (_, _) => _tryAutoPop(),
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final topInset = MediaQuery.paddingOf(context).top;
          final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
          final animationDuration = _isDismissingGesture
              ? Duration.zero
              : const Duration(milliseconds: 220);

          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topInset,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: 1 - _dismissFraction,
                    duration: animationDuration,
                    curve: Curves.easeOutCubic,
                    child: ColoredBox(color: backgroundColor),
                  ),
                ),
              ),
              Positioned.fill(
                top: topInset,
                child: AnimatedSlide(
                  offset: Offset(0, _dismissFraction),
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                  child: ColoredBox(
                    color: backgroundColor,
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ExcludeSemantics(
                              excluding: _showBottomPlayer,
                              child: IgnorePointer(
                                ignoring: _showBottomPlayer,
                                child: AnimatedOpacity(
                                  opacity: _showBottomPlayer ? 0 : 1,
                                  duration: const Duration(milliseconds: 180),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      4,
                                      24,
                                      184,
                                    ),
                                    child: Column(
                                      children: [
                                        GestureDetector(
                                          key: const ValueKey(
                                            'expanded-player-dismiss-region',
                                          ),
                                          behavior: HitTestBehavior.translucent,
                                          onVerticalDragUpdate: _dragToMinimize,
                                          onVerticalDragEnd: _settleMinimize,
                                          child: Column(
                                            children: [
                                              _Header(
                                                onClose: () =>
                                                    Navigator.of(context).pop(),
                                              ),
                                              const _ExpandedArtwork(),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const _ExpandedPlaybackControls(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          NotificationListener<DraggableScrollableNotification>(
                            onNotification: (notification) {
                              if ((_sheetExtent - notification.extent).abs() >
                                  .001) {
                                setState(
                                  () => _sheetExtent = notification.extent,
                                );
                              }
                              return false;
                            },
                            child: DraggableScrollableSheet(
                              controller: _sheetController,
                              initialChildSize: _minSheetSize,
                              minChildSize: _minSheetSize,
                              maxChildSize: 1,
                              snap: true,
                              snapSizes: const [_minSheetSize, 1],
                              snapAnimationDuration: const Duration(
                                milliseconds: 260,
                              ),
                              builder: (_, scrollController) =>
                                  _TranscriptSheet(
                                    scrollController: scrollController,
                                    showBottomPlayer: _showBottomPlayer,
                                    onHandleDragUpdate: _dragSheet,
                                    onHandleDragEnd: _settleSheet,
                                    onClose: () => Navigator.of(context).pop(),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Text(
          'Đang nghe',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 25),
            tooltip: 'Đóng về mini player',
          ),
        ),
      ],
    ),
  );
}

typedef _ExpandedMetadata = ({
  String? title,
  String? artist,
  Duration? duration,
});

class _ExpandedArtwork extends StatelessWidget {
  const _ExpandedArtwork();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _ExpandedMetadata>(
        selector: (state) {
          final item = state.currentItem;
          return (
            title: item?.title,
            artist: item?.artist,
            duration: state.duration > Duration.zero
                ? state.duration
                : item?.duration,
          );
        },
        builder: (context, metadata) => LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(
              constraints.maxWidth,
              MediaQuery.sizeOf(context).height * .45,
            );
            return Semantics(
              image: true,
              label: metadata.title == null
                  ? 'Ảnh bìa'
                  : 'Ảnh bìa ${metadata.title}',
              child: Stack(
                children: [
                  PlayerArtworkHero(size: size, radius: 28),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x78000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (metadata.title != null ||
                      metadata.artist != null ||
                      metadata.duration != null)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 23,
                      child: _ArtworkText(
                        title: metadata.title,
                        artist: metadata.artist,
                        duration: metadata.duration,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
}

class _ArtworkText extends StatelessWidget {
  const _ArtworkText({
    required this.title,
    required this.artist,
    required this.duration,
  });

  final String? title;
  final String? artist;
  final Duration? duration;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _DurationBadge(duration: duration),
      if (title != null) ...[
        const SizedBox(height: 12),
        Text(
          title!,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 29,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
      ],
      if (artist != null) ...[
        const SizedBox(height: 8),
        Text(
          artist!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xfffdf2f8),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .2),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 6),
        Text(
          _formatMetadataDuration(duration),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

String _formatMetadataDuration(Duration? duration) {
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

class _ExpandedPlaybackControls extends StatelessWidget {
  const _ExpandedPlaybackControls();

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, _ExpandedControlMode>(
        selector: (state) => (
          processingState: state.playback.processingState,
          failure: state.failure,
        ),
        builder: (context, mode) {
          if (mode.processingState == PlaybackProcessingState.error ||
              mode.failure != null) {
            return _ExpandedErrorNotice(failure: mode.failure);
          }

          if (mode.processingState == PlaybackProcessingState.buffering) {
            return const Column(
              children: [
                _ExpandedBufferingNotice(),
                SizedBox(height: 8),
                PlayerControlDock(),
              ],
            );
          }

          return const PlayerControlDock();
        },
      );
}

typedef _ExpandedControlMode = ({
  PlaybackProcessingState processingState,
  PlayerFailure? failure,
});

class _ExpandedBufferingNotice extends StatelessWidget {
  const _ExpandedBufferingNotice();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Đang tải',
    child: Row(
      key: const ValueKey('expanded-player-buffering-notice'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          key: ValueKey('expanded-player-buffering-spinner'),
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xfff2542c),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Đang tải',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xff64748b),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ExpandedErrorNotice extends StatelessWidget {
  const _ExpandedErrorNotice({required this.failure});

  final PlayerFailure? failure;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('expanded-player-error-notice'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
    decoration: BoxDecoration(
      color: const Color(0xfffff7ed),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xffffedd5)),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xffea580c),
          size: 28,
        ),
        const SizedBox(height: 8),
        Text(
          failure?.message ?? 'Không thể phát nội dung.',
          key: const ValueKey('expanded-player-error-message'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff9a3412),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (failure?.isRecoverable == true) ...[
          const SizedBox(height: 10),
          TextButton(
            key: const ValueKey('expanded-player-retry'),
            onPressed: () => unawaited(context.read<PlayerCubit>().retry()),
            child: const Text('Thử lại'),
          ),
        ],
      ],
    ),
  );
}

class _TranscriptSheet extends StatelessWidget {
  const _TranscriptSheet({
    required this.scrollController,
    required this.showBottomPlayer,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onClose,
  });
  final ScrollController scrollController;
  final bool showBottomPlayer;
  final GestureDragUpdateCallback onHandleDragUpdate;
  final GestureDragEndCallback onHandleDragEnd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      boxShadow: [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 30,
          offset: Offset(0, -8),
        ),
      ],
    ),
    child: Column(
      children: [
        Semantics(
          label: 'Kéo lời thoại để mở rộng',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: onHandleDragUpdate,
            onVerticalDragEnd: onHandleDragEnd,
            child: SizedBox(
              height: 32,
              width: double.infinity,
              child: Center(
                child: Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xfff2542c), Color(0xffec4899)],
                    ),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: showBottomPlayer
              ? Padding(
                  key: ValueKey('expanded-title'),
                  padding: EdgeInsets.only(top: 14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Lời thoại',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('sheet-close'),
                        tooltip: 'Đóng về mini player',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                )
              : const SizedBox(key: ValueKey('collapsed-space'), height: 19),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(top: 14),
            children: const [
              Text(
                "Welcome to The English We Speak, I'm Feifei and joining me is Roy.",
                style: TextStyle(
                  color: Color(0xff94a3b8),
                  fontSize: 16,
                  height: 1.55,
                ),
              ),
              SizedBox(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TranscriptMarker(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'In this program, we have a phrase we use when someone is ready for anything.',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.48,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Text(
                'Yes, and I must say you are looking very sharp today, Roy. Are you expecting...',
                style: TextStyle(
                  color: Color(0xffcbd5e1),
                  fontSize: 16,
                  height: 1.55,
                ),
              ),
              SizedBox(height: 30),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topLeft,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: showBottomPlayer
              ? const Padding(
                  key: ValueKey('bottom-player'),
                  padding: EdgeInsets.only(top: 8, bottom: 14),
                  child: _ExpandedPlaybackControls(),
                )
              : const SizedBox(key: ValueKey('no-bottom-player')),
        ),
      ],
    ),
  );
}

class _TranscriptMarker extends StatelessWidget {
  const _TranscriptMarker();
  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: 49,
    margin: const EdgeInsets.only(top: 3),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xfff2542c), Color(0xffec4899)],
      ),
      borderRadius: BorderRadius.circular(99),
    ),
  );
}
