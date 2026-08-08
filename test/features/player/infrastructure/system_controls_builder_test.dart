// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_command_policies.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/system_controls_builder.dart';
import '../support/player_test_data.dart';
import '../support/playback_snapshot_builder.dart';

void main() {
  group('SystemControlsBuilder state', () {
    test('does not advertise controls while idle', () {
      final result = SystemControlsBuilder.build(PlaybackSnapshot.idle);

      expect(result.controls, isEmpty);
      expect(result.systemActions, isEmpty);
    });

    test('does not advertise controls for initial loading without an item', () {
      final result = SystemControlsBuilder.build(
        buildPlaybackSnapshot(processingState: PlaybackProcessingState.loading),
      );

      expect(result.controls, isEmpty);
      expect(result.systemActions, isEmpty);
    });

    test('advertises Play, Stop, seek and skip controls when paused', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          processingState: PlaybackProcessingState.ready,
          currentIndex: 1,
          position: const Duration(seconds: 4),
          duration: const Duration(minutes: 2),
        ),
      );

      expect(_controlActions(result), contains(audio_service.MediaAction.play));
      expect(_controlActions(result), contains(audio_service.MediaAction.stop));
      expect(
        _controlActions(result),
        containsAll(<audio_service.MediaAction>[
          audio_service.MediaAction.rewind,
          audio_service.MediaAction.fastForward,
          audio_service.MediaAction.skipToPrevious,
          audio_service.MediaAction.skipToNext,
        ]),
      );
      expect(
        result.systemActions,
        containsAll(<audio_service.MediaAction>[
          audio_service.MediaAction.seek,
          audio_service.MediaAction.seekBackward,
          audio_service.MediaAction.seekForward,
        ]),
      );
    });

    test('advertises Pause while ready and playing', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          processingState: PlaybackProcessingState.ready,
          playing: true,
          duration: const Duration(minutes: 2),
        ),
      );

      expect(
        _controlActions(result),
        contains(audio_service.MediaAction.pause),
      );
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.play)),
      );
    });

    test('keeps Pause while buffering with playing intent', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          processingState: PlaybackProcessingState.buffering,
          playing: true,
          duration: const Duration(minutes: 2),
        ),
      );

      expect(
        _controlActions(result),
        contains(audio_service.MediaAction.pause),
      );
      expect(_controlActions(result), contains(audio_service.MediaAction.stop));
    });

    test('keeps Play and Stop while an active paused item is loading', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          processingState: PlaybackProcessingState.loading,
          duration: const Duration(minutes: 2),
        ),
      );

      expect(_controlActions(result), contains(audio_service.MediaAction.play));
      expect(_controlActions(result), contains(audio_service.MediaAction.stop));
      expect(result.systemActions, isEmpty);
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.rewind)),
      );
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.fastForward)),
      );
    });

    test('keeps Pause and Stop while an active playing item is loading', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          processingState: PlaybackProcessingState.loading,
          playing: true,
          duration: const Duration(minutes: 2),
        ),
      );

      expect(
        _controlActions(result),
        contains(audio_service.MediaAction.pause),
      );
      expect(_controlActions(result), contains(audio_service.MediaAction.stop));
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.play)),
      );
      expect(result.systemActions, isEmpty);
    });

    test('advertises Play as Replay when completed', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          processingState: PlaybackProcessingState.completed,
          duration: const Duration(minutes: 2),
          position: const Duration(minutes: 2),
        ),
      );

      expect(_controlActions(result), contains(audio_service.MediaAction.play));
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.pause)),
      );
      expect(_controlActions(result), contains(audio_service.MediaAction.stop));
    });

    test('keeps Stop but does not advertise unavailable commands on error', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          processingState: PlaybackProcessingState.error,
          failure: const PlayerFailure(
            code: 'network',
            message: 'Network unavailable.',
            isRecoverable: true,
          ),
        ),
      );

      expect(_controlActions(result), {audio_service.MediaAction.stop});
      expect(result.systemActions, isEmpty);
    });

    test('does not advertise seek or skip actions for unknown duration', () {
      final result = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          processingState: PlaybackProcessingState.ready,
          currentIndex: 1,
          duration: Duration.zero,
        ),
      );

      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.rewind)),
      );
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.fastForward)),
      );
      expect(result.systemActions, isEmpty);
      expect(
        _controlActions(result),
        containsAll(<audio_service.MediaAction>[
          audio_service.MediaAction.skipToPrevious,
          audio_service.MediaAction.skipToNext,
        ]),
      );
    });
  });

  group('SystemControlsBuilder queue boundaries', () {
    test('keeps active queue navigation while loading', () {
      final first = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          currentIndex: 0,
          processingState: PlaybackProcessingState.loading,
        ),
      );
      final middle = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          currentIndex: 1,
          processingState: PlaybackProcessingState.loading,
        ),
      );
      final last = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          currentIndex: 2,
          processingState: PlaybackProcessingState.loading,
        ),
      );

      expect(
        _controlActions(first),
        contains(audio_service.MediaAction.skipToNext),
      );
      expect(
        _controlActions(first),
        isNot(contains(audio_service.MediaAction.skipToPrevious)),
      );
      expect(
        _controlActions(middle),
        containsAll(<audio_service.MediaAction>[
          audio_service.MediaAction.skipToPrevious,
          audio_service.MediaAction.skipToNext,
        ]),
      );
      expect(
        _controlActions(last),
        contains(audio_service.MediaAction.skipToPrevious),
      );
      expect(
        _controlActions(last),
        isNot(contains(audio_service.MediaAction.skipToNext)),
      );
      expect(first.systemActions, isEmpty);
      expect(middle.systemActions, isEmpty);
      expect(last.systemActions, isEmpty);
    });

    test(
      'advertises next and previous only in the effective queue direction',
      () {
        final first = SystemControlsBuilder.build(
          _snapshot(
            queueLength: 3,
            currentIndex: 0,
            duration: const Duration(minutes: 2),
          ),
        );
        final middle = SystemControlsBuilder.build(
          _snapshot(
            queueLength: 3,
            currentIndex: 1,
            duration: const Duration(minutes: 2),
          ),
        );
        final last = SystemControlsBuilder.build(
          _snapshot(
            queueLength: 3,
            currentIndex: 2,
            duration: const Duration(minutes: 2),
          ),
        );

        expect(
          _controlActions(first),
          contains(audio_service.MediaAction.skipToNext),
        );
        expect(
          _controlActions(first),
          isNot(contains(audio_service.MediaAction.skipToPrevious)),
        );
        expect(
          _controlActions(middle),
          containsAll(<audio_service.MediaAction>[
            audio_service.MediaAction.skipToPrevious,
            audio_service.MediaAction.skipToNext,
          ]),
        );
        expect(
          _controlActions(last),
          contains(audio_service.MediaAction.skipToPrevious),
        );
        expect(
          _controlActions(last),
          isNot(contains(audio_service.MediaAction.skipToNext)),
        );
      },
    );

    test('wraps next and previous at the repeat-all boundary', () {
      final first = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          currentIndex: 0,
          repeatMode: PlayerRepeatMode.all,
        ),
      );
      final last = SystemControlsBuilder.build(
        _snapshot(
          queueLength: 3,
          currentIndex: 2,
          repeatMode: PlayerRepeatMode.all,
        ),
      );

      expect(
        _controlActions(first),
        contains(audio_service.MediaAction.skipToPrevious),
      );
      expect(
        _controlActions(last),
        contains(audio_service.MediaAction.skipToNext),
      );
    });

    test(
      'advertises Previous at the first item when it restarts after 3 seconds',
      () {
        final result = SystemControlsBuilder.build(
          _snapshot(
            queueLength: 3,
            currentIndex: 0,
            position:
                PlayerCommandPolicies.previousRestartThreshold +
                const Duration(microseconds: 1),
          ),
        );

        expect(
          _controlActions(result),
          contains(audio_service.MediaAction.skipToPrevious),
        );
      },
    );

    test('does not advertise boundary navigation for repeat off or one', () {
      for (final repeatMode in <PlayerRepeatMode>[
        PlayerRepeatMode.off,
        PlayerRepeatMode.one,
      ]) {
        final result = SystemControlsBuilder.build(
          _snapshot(queueLength: 3, currentIndex: 0, repeatMode: repeatMode),
        );

        expect(
          _controlActions(result),
          isNot(contains(audio_service.MediaAction.skipToPrevious)),
        );
      }
    });

    test('does not use queue navigation for rewind or fast-forward', () {
      final result = SystemControlsBuilder.build(
        _snapshot(queueLength: 1, duration: const Duration(minutes: 2)),
      );

      expect(
        _controlActions(result),
        containsAll(<audio_service.MediaAction>[
          audio_service.MediaAction.rewind,
          audio_service.MediaAction.fastForward,
        ]),
      );
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.skipToNext)),
      );
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.skipToPrevious)),
      );
    });
  });

  group('SystemControlsBuilder capabilities', () {
    test(
      'filters unsupported optional actions without removing core controls',
      () {
        final result = SystemControlsBuilder.build(
          _snapshot(
            queueLength: 3,
            currentIndex: 1,
            duration: const Duration(minutes: 2),
          ),
          capabilities: SystemControlCapabilities(<audio_service.MediaAction>{
            audio_service.MediaAction.play,
            audio_service.MediaAction.stop,
            audio_service.MediaAction.seek,
          }),
        );

        expect(
          _controlActions(result),
          containsAll(<audio_service.MediaAction>[
            audio_service.MediaAction.play,
            audio_service.MediaAction.stop,
          ]),
        );
        expect(
          _controlActions(result),
          isNot(contains(audio_service.MediaAction.rewind)),
        );
        expect(
          _controlActions(result),
          isNot(contains(audio_service.MediaAction.fastForward)),
        );
        expect(result.systemActions, {audio_service.MediaAction.seek});
      },
    );

    test('filters core actions independently', () {
      final result = SystemControlsBuilder.build(
        _snapshot(playing: true, duration: const Duration(minutes: 2)),
        capabilities: SystemControlCapabilities(<audio_service.MediaAction>{
          audio_service.MediaAction.stop,
          audio_service.MediaAction.fastForward,
        }),
      );

      expect(_controlActions(result), contains(audio_service.MediaAction.stop));
      expect(
        _controlActions(result),
        contains(audio_service.MediaAction.fastForward),
      );
      expect(
        _controlActions(result),
        isNot(contains(audio_service.MediaAction.pause)),
      );
      expect(result.systemActions, isEmpty);
    });
  });
}

Set<audio_service.MediaAction> _controlActions(SystemControls controls) =>
    controls.controls.map((control) => control.action).toSet();

PlaybackSnapshot _snapshot({
  int queueLength = 1,
  int currentIndex = 0,
  PlaybackProcessingState processingState = PlaybackProcessingState.ready,
  bool playing = false,
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 30),
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off,
  PlayerFailure? failure,
}) {
  final queue = List.generate(
    queueLength,
    (index) => testPlayerItem(id: 'track-$index'),
  );
  return buildPlaybackSnapshot(
    currentItem: queue[currentIndex],
    queue: queue,
    currentIndex: currentIndex,
    processingState: processingState,
    playing: playing,
    position: position,
    duration: duration,
    repeatMode: repeatMode,
    failure: failure,
  );
}
