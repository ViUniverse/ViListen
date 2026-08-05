import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/playback_mappers.dart';

void main() {
  group('PlaybackMappers.mapProcessingState', () {
    test('maps every just_audio processing state', () {
      expect(
        just_audio.ProcessingState.values.map(
          PlaybackMappers.mapProcessingState,
        ),
        [
          PlaybackProcessingState.idle,
          PlaybackProcessingState.loading,
          PlaybackProcessingState.buffering,
          PlaybackProcessingState.ready,
          PlaybackProcessingState.completed,
        ],
      );
    });

    test('applies a domain failure as the error overlay', () {
      const failure = PlayerFailure(
        code: 'network',
        message: 'Network unavailable.',
        isRecoverable: true,
        itemId: 'track-1',
      );

      expect(
        PlaybackMappers.mapProcessingState(
          just_audio.ProcessingState.buffering,
          failure: failure,
        ),
        PlaybackProcessingState.error,
      );
    });

    test('maps a valid engine event after retry and clears the overlay', () {
      const failure = PlayerFailure(
        code: 'network',
        message: 'Network unavailable.',
        isRecoverable: true,
        itemId: 'track-1',
      );

      expect(
        PlaybackMappers.mapProcessingState(
          just_audio.ProcessingState.loading,
          failure: failure,
        ),
        PlaybackProcessingState.error,
      );

      final recoveredEngineState = just_audio.PlayerState(
        true,
        just_audio.ProcessingState.ready,
      );

      expect(
        PlaybackMappers.mapProcessingState(
          recoveredEngineState.processingState,
        ),
        PlaybackProcessingState.ready,
      );
    });
  });

  group('PlaybackMappers repeat', () {
    test('maps every domain repeat mode to just_audio', () {
      expect(
        PlayerRepeatMode.values.map(PlaybackMappers.toEngineRepeat),
        just_audio.LoopMode.values,
      );
    });

    test('maps every just_audio repeat mode to the domain', () {
      expect(
        just_audio.LoopMode.values.map(PlaybackMappers.fromEngineRepeat),
        PlayerRepeatMode.values,
      );
    });

    test('maps every domain repeat mode to audio_service', () {
      expect(
        PlayerRepeatMode.values.map(PlaybackMappers.toAudioServiceRepeat),
        const [
          audio_service.AudioServiceRepeatMode.none,
          audio_service.AudioServiceRepeatMode.one,
          audio_service.AudioServiceRepeatMode.all,
        ],
      );
    });

    test('maps every audio_service repeat mode to the domain', () {
      expect(
        audio_service.AudioServiceRepeatMode.values.map(
          PlaybackMappers.fromAudioServiceRepeat,
        ),
        [
          PlayerRepeatMode.off,
          PlayerRepeatMode.one,
          PlayerRepeatMode.all,
          PlayerRepeatMode.all,
        ],
      );
    });
  });

  group('PlaybackMappers shuffle', () {
    test('maps disabled and enabled shuffle to audio_service', () {
      expect([false, true].map(PlaybackMappers.toAudioServiceShuffle), const [
        audio_service.AudioServiceShuffleMode.none,
        audio_service.AudioServiceShuffleMode.all,
      ]);
    });

    test('maps every audio_service shuffle mode to its enabled state', () {
      expect(
        audio_service.AudioServiceShuffleMode.values.map(
          PlaybackMappers.fromAudioServiceShuffle,
        ),
        [false, true, true],
      );
    });
  });
}
