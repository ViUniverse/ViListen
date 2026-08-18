// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/player_command_policies.dart';
import 'package:vi_listen/features/player/infrastructure/player_audio_service_config.dart';

void main() {
  group('createPlayerAudioServiceConfig', () {
    test('creates the canonical player audio service config', () {
      final config = createPlayerAudioServiceConfig();

      expect(config.androidNotificationChannelId, 'com.vilisten.playback');
      expect(config.androidNotificationChannelName, 'Đang phát');
      expect(config.fastForwardInterval, PlayerCommandPolicies.skipInterval);
      expect(config.rewindInterval, PlayerCommandPolicies.skipInterval);
      expect(config.androidStopForegroundOnPause, isFalse);
    });

    test('defines the channel ID only once in production Dart source', () {
      const channelId = 'com.vilisten.playback';
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final occurrences = dartFiles.fold<int>(
        0,
        (total, file) =>
            total + channelId.allMatches(file.readAsStringSync()).length,
      );

      expect(occurrences, 1);
    });
  });
}
