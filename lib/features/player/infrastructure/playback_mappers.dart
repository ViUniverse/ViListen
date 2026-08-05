import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

/// Maps playback values between the domain and the platform packages.
abstract final class PlaybackMappers {
  /// Maps the five processing states emitted by just_audio.
  ///
  /// [failure] is an application-level overlay because just_audio reports
  /// failures on a separate error stream. A successful engine event must be
  /// passed without a failure so a retry can clear the domain error state.
  static PlaybackProcessingState mapProcessingState(
    just_audio.ProcessingState state, {
    PlayerFailure? failure,
  }) {
    if (failure != null) {
      return PlaybackProcessingState.error;
    }

    return switch (state) {
      just_audio.ProcessingState.idle => PlaybackProcessingState.idle,
      just_audio.ProcessingState.loading => PlaybackProcessingState.loading,
      just_audio.ProcessingState.buffering => PlaybackProcessingState.buffering,
      just_audio.ProcessingState.ready => PlaybackProcessingState.ready,
      just_audio.ProcessingState.completed => PlaybackProcessingState.completed,
    };
  }

  static just_audio.LoopMode toEngineRepeat(PlayerRepeatMode mode) =>
      switch (mode) {
        PlayerRepeatMode.off => just_audio.LoopMode.off,
        PlayerRepeatMode.one => just_audio.LoopMode.one,
        PlayerRepeatMode.all => just_audio.LoopMode.all,
      };

  static PlayerRepeatMode fromEngineRepeat(just_audio.LoopMode mode) =>
      switch (mode) {
        just_audio.LoopMode.off => PlayerRepeatMode.off,
        just_audio.LoopMode.one => PlayerRepeatMode.one,
        just_audio.LoopMode.all => PlayerRepeatMode.all,
      };

  static audio_service.AudioServiceRepeatMode toAudioServiceRepeat(
    PlayerRepeatMode mode,
  ) => switch (mode) {
    PlayerRepeatMode.off => audio_service.AudioServiceRepeatMode.none,
    PlayerRepeatMode.one => audio_service.AudioServiceRepeatMode.one,
    PlayerRepeatMode.all => audio_service.AudioServiceRepeatMode.all,
  };

  static PlayerRepeatMode fromAudioServiceRepeat(
    audio_service.AudioServiceRepeatMode mode,
  ) => switch (mode) {
    audio_service.AudioServiceRepeatMode.none => PlayerRepeatMode.off,
    audio_service.AudioServiceRepeatMode.one => PlayerRepeatMode.one,
    audio_service.AudioServiceRepeatMode.all => PlayerRepeatMode.all,
    // Player v1 has one effective queue, so audio_service's group repeat
    // has the closest supported domain meaning: repeat all.
    audio_service.AudioServiceRepeatMode.group => PlayerRepeatMode.all,
  };

  static audio_service.AudioServiceShuffleMode toAudioServiceShuffle(
    bool enabled,
  ) => enabled
      ? audio_service.AudioServiceShuffleMode.all
      : audio_service.AudioServiceShuffleMode.none;

  static bool fromAudioServiceShuffle(
    audio_service.AudioServiceShuffleMode mode,
  ) => switch (mode) {
    audio_service.AudioServiceShuffleMode.none => false,
    audio_service.AudioServiceShuffleMode.all => true,
    // The domain exposes only whether shuffle is enabled, not its scope.
    audio_service.AudioServiceShuffleMode.group => true,
  };
}
