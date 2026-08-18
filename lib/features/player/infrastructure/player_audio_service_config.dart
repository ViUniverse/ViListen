// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart';
import 'package:vi_listen/features/player/application/player_command_policies.dart';

AudioServiceConfig createPlayerAudioServiceConfig() => const AudioServiceConfig(
  androidNotificationChannelId: 'com.vilisten.playback',
  androidNotificationChannelName: 'Đang phát',
  fastForwardInterval: PlayerCommandPolicies.skipInterval,
  rewindInterval: PlayerCommandPolicies.skipInterval,
  androidStopForegroundOnPause: false,
);
