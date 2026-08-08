// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:vi_listen/features/player/application/player_command_policies.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';

/// Platform actions that may be advertised by the system media session.
final class SystemControlCapabilities {
  SystemControlCapabilities(
    Iterable<audio_service.MediaAction> supportedActions,
  ) : supportedActions = Set<audio_service.MediaAction>.unmodifiable(
        supportedActions,
      );

  static final all = SystemControlCapabilities(<audio_service.MediaAction>{
    audio_service.MediaAction.play,
    audio_service.MediaAction.pause,
    audio_service.MediaAction.stop,
    audio_service.MediaAction.seek,
    audio_service.MediaAction.rewind,
    audio_service.MediaAction.fastForward,
    audio_service.MediaAction.skipToPrevious,
    audio_service.MediaAction.skipToNext,
    audio_service.MediaAction.seekBackward,
    audio_service.MediaAction.seekForward,
  });

  final Set<audio_service.MediaAction> supportedActions;

  bool supports(audio_service.MediaAction action) =>
      supportedActions.contains(action);
}

/// The controls and non-button actions for one confirmed playback snapshot.
final class SystemControls {
  SystemControls({
    required List<audio_service.MediaControl> controls,
    required Set<audio_service.MediaAction> systemActions,
  }) : controls = List<audio_service.MediaControl>.unmodifiable(controls),
       systemActions = Set<audio_service.MediaAction>.unmodifiable(
         systemActions,
       );

  final List<audio_service.MediaControl> controls;
  final Set<audio_service.MediaAction> systemActions;
}

/// Builds system media controls without performing playback side effects.
abstract final class SystemControlsBuilder {
  static SystemControls build(
    PlaybackSnapshot snapshot, {
    SystemControlCapabilities? capabilities,
  }) {
    final supported = capabilities ?? SystemControlCapabilities.all;
    final controls = <audio_service.MediaControl>[];
    final systemActions = <audio_service.MediaAction>{};

    if (snapshot.currentItem == null ||
        snapshot.processingState == PlaybackProcessingState.idle) {
      return SystemControls(controls: controls, systemActions: systemActions);
    }

    if (snapshot.processingState == PlaybackProcessingState.error) {
      _addControl(
        controls,
        audio_service.MediaControl.stop,
        audio_service.MediaAction.stop,
        supported,
      );
      return SystemControls(controls: controls, systemActions: systemActions);
    }

    _addMainControl(controls, snapshot, supported);
    _addControl(
      controls,
      audio_service.MediaControl.stop,
      audio_service.MediaAction.stop,
      supported,
    );

    if (_canSeek(snapshot)) {
      _addSystemAction(
        systemActions,
        audio_service.MediaAction.seek,
        supported,
      );
      _addControl(
        controls,
        audio_service.MediaControl.rewind,
        audio_service.MediaAction.rewind,
        supported,
      );
      _addControl(
        controls,
        audio_service.MediaControl.fastForward,
        audio_service.MediaAction.fastForward,
        supported,
      );
      _addSystemAction(
        systemActions,
        audio_service.MediaAction.seekBackward,
        supported,
      );
      _addSystemAction(
        systemActions,
        audio_service.MediaAction.seekForward,
        supported,
      );
    }

    if (_canAdvertiseNext(snapshot)) {
      _addControl(
        controls,
        audio_service.MediaControl.skipToNext,
        audio_service.MediaAction.skipToNext,
        supported,
      );
    }
    if (_canAdvertisePrevious(snapshot)) {
      _addControl(
        controls,
        audio_service.MediaControl.skipToPrevious,
        audio_service.MediaAction.skipToPrevious,
        supported,
      );
    }

    return SystemControls(controls: controls, systemActions: systemActions);
  }

  static void _addMainControl(
    List<audio_service.MediaControl> controls,
    PlaybackSnapshot snapshot,
    SystemControlCapabilities capabilities,
  ) {
    final control = snapshot.isCompleted || !snapshot.playing
        ? audio_service.MediaControl.play
        : audio_service.MediaControl.pause;
    final action = snapshot.isCompleted || !snapshot.playing
        ? audio_service.MediaAction.play
        : audio_service.MediaAction.pause;
    _addControl(controls, control, action, capabilities);
  }

  static bool _canSeek(PlaybackSnapshot snapshot) =>
      snapshot.processingState == PlaybackProcessingState.ready ||
          snapshot.processingState == PlaybackProcessingState.buffering ||
          snapshot.processingState == PlaybackProcessingState.completed
      ? snapshot.duration > Duration.zero
      : false;

  static bool _canAdvertiseNext(PlaybackSnapshot snapshot) {
    if (!_hasValidCurrentIndex(snapshot)) {
      return false;
    }
    return snapshot.hasNext ||
        snapshot.repeatMode == PlayerRepeatMode.all &&
            snapshot.queue.length > 1;
  }

  static bool _canAdvertisePrevious(PlaybackSnapshot snapshot) {
    if (!_hasValidCurrentIndex(snapshot)) {
      return false;
    }
    return snapshot.hasPrevious ||
        snapshot.position > PlayerCommandPolicies.previousRestartThreshold ||
        snapshot.repeatMode == PlayerRepeatMode.all &&
            snapshot.queue.length > 1;
  }

  static bool _hasValidCurrentIndex(PlaybackSnapshot snapshot) {
    final index = snapshot.currentIndex;
    return index != null && index >= 0 && index < snapshot.queue.length;
  }

  static void _addControl(
    List<audio_service.MediaControl> controls,
    audio_service.MediaControl control,
    audio_service.MediaAction action,
    SystemControlCapabilities capabilities,
  ) {
    if (capabilities.supports(action)) {
      controls.add(control);
    }
  }

  static void _addSystemAction(
    Set<audio_service.MediaAction> systemActions,
    audio_service.MediaAction action,
    SystemControlCapabilities capabilities,
  ) {
    if (capabilities.supports(action)) {
      systemActions.add(action);
    }
  }
}
