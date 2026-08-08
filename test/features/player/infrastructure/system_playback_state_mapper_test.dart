// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/system_controls_builder.dart';
import 'package:vi_listen/features/player/infrastructure/system_playback_state_mapper.dart';
import '../support/player_test_data.dart';
import '../support/playback_snapshot_builder.dart';

void main() {
  group('SystemPlaybackStateMapper', () {
    test('maps every domain processing state', () {
      final mapper = SystemPlaybackStateMapper(
        now: () => DateTime.utc(2026, 8, 5),
      );

      expect(
        PlaybackProcessingState.values.map(
          (processingState) => mapper
              .map(_snapshot(processingState: processingState))
              .processingState,
        ),
        [
          audio_service.AudioProcessingState.idle,
          audio_service.AudioProcessingState.loading,
          audio_service.AudioProcessingState.buffering,
          audio_service.AudioProcessingState.ready,
          audio_service.AudioProcessingState.completed,
          audio_service.AudioProcessingState.error,
        ],
      );
    });

    test('maps controls and system actions from SystemControlsBuilder', () {
      final snapshot = _snapshot(
        queueLength: 3,
        currentIndex: 1,
        playing: false,
        position: const Duration(seconds: 4),
        duration: const Duration(minutes: 2),
      );
      final expected = SystemControlsBuilder.build(snapshot);
      final state = SystemPlaybackStateMapper(
        now: () => DateTime.utc(2026, 8, 5),
      ).map(snapshot);

      expect(
        state.controls.map((control) => control.action),
        expected.controls.map((control) => control.action),
      );
      expect(state.systemActions, expected.systemActions);
    });

    test('maps position, buffer, speed, queue index, repeat and shuffle', () {
      final snapshot = _snapshot(
        queueLength: 3,
        currentIndex: 2,
        playing: true,
        position: const Duration(seconds: 17, milliseconds: 250),
        bufferedPosition: const Duration(seconds: 42, milliseconds: 500),
        speed: 1.25,
        repeatMode: PlayerRepeatMode.all,
        shuffleEnabled: true,
      );
      final state = SystemPlaybackStateMapper(
        now: () => DateTime.utc(2026, 8, 5),
      ).map(snapshot);

      expect(state.playing, isTrue);
      expect(
        state.updatePosition,
        const Duration(seconds: 17, milliseconds: 250),
      );
      expect(
        state.bufferedPosition,
        const Duration(seconds: 42, milliseconds: 500),
      );
      expect(state.speed, 1.25);
      expect(state.queueIndex, 2);
      expect(state.repeatMode, audio_service.AudioServiceRepeatMode.all);
      expect(state.shuffleMode, audio_service.AudioServiceShuffleMode.all);
    });

    test('takes updateTime once at publication', () {
      final publicationTime = DateTime.utc(2026, 8, 5, 12, 30);
      var nowCalls = 0;
      final mapper = SystemPlaybackStateMapper(
        now: () {
          nowCalls += 1;
          return publicationTime;
        },
      );

      final state = mapper.map(_snapshot());

      expect(state.updateTime, publicationTime);
      expect(nowCalls, 1);
    });

    test('maps canonical idle without OS controls or error data', () {
      final state = SystemPlaybackStateMapper(
        now: () => DateTime.utc(2026, 8, 5),
      ).map(PlaybackSnapshot.idle);

      expect(state.processingState, audio_service.AudioProcessingState.idle);
      expect(state.playing, isFalse);
      expect(state.controls, isEmpty);
      expect(state.systemActions, isEmpty);
      expect(state.updatePosition, Duration.zero);
      expect(state.bufferedPosition, Duration.zero);
      expect(state.speed, 1.0);
      expect(state.queueIndex, isNull);
      expect(state.repeatMode, audio_service.AudioServiceRepeatMode.none);
      expect(state.shuffleMode, audio_service.AudioServiceShuffleMode.none);
      expect(state.errorCode, isNull);
      expect(state.errorMessage, isNull);
    });

    test('maps PLR-007 error codes with sanitized messages', () {
      final cases = <({String failureCode, int osCode, String message})>[
        (failureCode: 'network', osCode: 1001, message: 'Network unavailable.'),
        (
          failureCode: 'not_found',
          osCode: 1002,
          message: 'Audio source not found.',
        ),
        (
          failureCode: 'unsupported_format',
          osCode: 1003,
          message: 'Audio format is not supported.',
        ),
        (
          failureCode: 'audio_output',
          osCode: 1004,
          message: 'Audio output is unavailable.',
        ),
        (
          failureCode: 'stopFailed',
          osCode: 1005,
          message: 'Playback stop failed.',
        ),
        (
          failureCode: 'unknown_engine',
          osCode: 1099,
          message: 'Playback failed.',
        ),
        (
          failureCode: 'bootstrapUnavailable',
          osCode: 1100,
          message: 'Audio service is unavailable.',
        ),
      ];

      for (final testCase in cases) {
        final secret = 'signed-url-token-${testCase.failureCode}';
        final state =
            SystemPlaybackStateMapper(now: () => DateTime.utc(2026, 8, 5)).map(
              _snapshot(
                playing: true,
                processingState: PlaybackProcessingState.error,
                failure: PlayerFailure(
                  code: testCase.failureCode,
                  message: secret,
                  isRecoverable: false,
                ),
              ),
            );

        expect(state.processingState, audio_service.AudioProcessingState.error);
        expect(state.errorCode, testCase.osCode);
        expect(state.errorMessage, testCase.message);
        expect(state.errorMessage, isNot(contains(secret)));
        if (testCase.failureCode == 'stopFailed') {
          expect(state.playing, isTrue);
        } else {
          expect(state.playing, isFalse);
        }
      }
    });

    test(
      'uses the unknown OS error fallback for missing or unknown failure',
      () {
        final mapper = SystemPlaybackStateMapper(
          now: () => DateTime.utc(2026, 8, 5),
        );

        final missingFailure = mapper.map(
          _snapshot(processingState: PlaybackProcessingState.error),
        );
        final unknownFailure = mapper.map(
          _snapshot(
            processingState: PlaybackProcessingState.error,
            failure: const PlayerFailure(
              code: 'not-a-canonical-code',
              message: 'raw platform exception',
              isRecoverable: false,
            ),
          ),
        );

        for (final state in [missingFailure, unknownFailure]) {
          expect(state.errorCode, 1099);
          expect(state.errorMessage, 'Playback failed.');
          expect(state.playing, isFalse);
        }
      },
    );
  });
}

PlaybackSnapshot _snapshot({
  int queueLength = 1,
  int currentIndex = 0,
  PlaybackProcessingState processingState = PlaybackProcessingState.ready,
  bool playing = false,
  Duration position = Duration.zero,
  Duration bufferedPosition = Duration.zero,
  Duration duration = const Duration(seconds: 90),
  double speed = 1.0,
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off,
  bool shuffleEnabled = false,
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
    bufferedPosition: bufferedPosition,
    duration: duration,
    speed: speed,
    repeatMode: repeatMode,
    shuffleEnabled: shuffleEnabled,
    failure: failure,
  );
}
