// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/playback_mappers.dart';
import 'package:vi_listen/features/player/infrastructure/system_controls_builder.dart';

/// Maps one confirmed domain snapshot to the state published to the OS.
final class SystemPlaybackStateMapper {
  SystemPlaybackStateMapper({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  audio_service.PlaybackState map(PlaybackSnapshot snapshot) {
    final controls = SystemControlsBuilder.build(snapshot);
    final error = _mapError(snapshot);
    final updateTime = _now();

    return audio_service.PlaybackState(
      processingState: _mapProcessingState(snapshot.processingState),
      playing: _mapPlaying(snapshot, error),
      controls: controls.controls,
      systemActions: controls.systemActions,
      updatePosition: snapshot.position,
      bufferedPosition: snapshot.bufferedPosition,
      speed: snapshot.speed,
      updateTime: updateTime,
      errorCode: error?.code,
      errorMessage: error?.message,
      repeatMode: PlaybackMappers.toAudioServiceRepeat(snapshot.repeatMode),
      shuffleMode: PlaybackMappers.toAudioServiceShuffle(
        snapshot.shuffleEnabled,
      ),
      queueIndex: snapshot.currentIndex,
    );
  }

  static audio_service.AudioProcessingState _mapProcessingState(
    PlaybackProcessingState state,
  ) => switch (state) {
    PlaybackProcessingState.idle => audio_service.AudioProcessingState.idle,
    PlaybackProcessingState.loading =>
      audio_service.AudioProcessingState.loading,
    PlaybackProcessingState.buffering =>
      audio_service.AudioProcessingState.buffering,
    PlaybackProcessingState.ready => audio_service.AudioProcessingState.ready,
    PlaybackProcessingState.completed =>
      audio_service.AudioProcessingState.completed,
    PlaybackProcessingState.error => audio_service.AudioProcessingState.error,
  };

  static bool _mapPlaying(
    PlaybackSnapshot snapshot,
    _SystemPlaybackError? error,
  ) {
    if (error == null) {
      return snapshot.playing;
    }

    // PLR-007 keeps the engine-confirmed playing state only for stopFailed.
    return snapshot.failure?.code == 'stopFailed' ? snapshot.playing : false;
  }

  static _SystemPlaybackError? _mapError(PlaybackSnapshot snapshot) {
    if (snapshot.processingState != PlaybackProcessingState.error) {
      return null;
    }

    final failureCode = snapshot.failure?.code;
    return _systemErrors[failureCode] ?? _SystemPlaybackError.unknown;
  }
}

final class _SystemPlaybackError {
  const _SystemPlaybackError(this.code, this.message);

  static const unknown = _SystemPlaybackError(1099, 'Playback failed.');

  final int code;
  final String message;
}

const _systemErrors = <String, _SystemPlaybackError>{
  'network': _SystemPlaybackError(1001, 'Network unavailable.'),
  'load': _SystemPlaybackError(1001, 'Network unavailable.'),
  'not_found': _SystemPlaybackError(1002, 'Audio source not found.'),
  'unsupported_format': _SystemPlaybackError(
    1003,
    'Audio format is not supported.',
  ),
  'audio_output': _SystemPlaybackError(1004, 'Audio output is unavailable.'),
  'stopFailed': _SystemPlaybackError(1005, 'Playback stop failed.'),
  'bootstrapUnavailable': _SystemPlaybackError(
    1100,
    'Audio service is unavailable.',
  ),
  'unknown_engine': _SystemPlaybackError.unknown,
};
