// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/player_failure_mapper.dart';

void main() {
  const mapper = PlayerFailureMapper();

  group('PlayerFailureMapper', () {
    test('normalizes network failures as recoverable', () {
      final failure = mapper.map(
        PlayerException(0, 'Network connection failed.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.android,
        itemId: 'track-1',
      );

      expect(
        failure,
        const PlayerFailure(
          code: 'network',
          message: 'Network unavailable.',
          isRecoverable: true,
          itemId: 'track-1',
        ),
      );
    });

    test('normalizes timeout failures as network failures', () {
      final failure = mapper.map(
        TimeoutException('request timed out'),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.unknown,
        itemId: 'track-1',
      );

      expect(failure?.code, 'network');
      expect(failure?.isRecoverable, isTrue);
      expect(failure?.itemId, 'track-1');
    });

    test('normalizes Apple not-found errors as non-recoverable', () {
      final failure = mapper.map(
        PlayerException(-1100, 'The file could not be found.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.apple,
        itemId: 'track-1',
      );

      expect(
        failure,
        const PlayerFailure(
          code: 'not_found',
          message: 'Audio source not found.',
          isRecoverable: false,
          itemId: 'track-1',
        ),
      );
    });

    test('normalizes unsupported format failures as non-recoverable', () {
      final failure = mapper.map(
        PlayerException(0, 'Unsupported audio codec.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.android,
        itemId: 'track-1',
      );

      expect(failure?.code, 'unsupported_format');
      expect(failure?.message, 'Audio format is not supported.');
      expect(failure?.isRecoverable, isFalse);
      expect(failure?.itemId, 'track-1');
    });

    test('normalizes audio output failures as recoverable', () {
      final failure = mapper.map(
        PlayerException(0, 'AudioTrack output device unavailable.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.android,
        itemId: 'track-1',
      );

      expect(failure?.code, 'audio_output');
      expect(failure?.message, 'Audio output is unavailable.');
      expect(failure?.isRecoverable, isTrue);
      expect(failure?.itemId, 'track-1');
    });

    test(
      'uses a safe unknown fallback without exposing raw exception text',
      () {
        const secret = 'signed-url-token=do-not-display';
        final failure = mapper.map(
          StateError(secret),
          context: PlayerFailureContext.runtime,
          platform: PlayerFailurePlatform.web,
          itemId: 'track-1',
        );

        expect(
          failure,
          const PlayerFailure(
            code: 'unknown_engine',
            message: 'Playback failed.',
            isRecoverable: false,
            itemId: 'track-1',
          ),
        );
        expect(failure?.message, isNot(contains(secret)));
      },
    );

    test('does not expose interrupted loads as user-visible failures', () {
      final failure = mapper.map(
        PlayerInterruptedException('Loading interrupted.'),
        context: PlayerFailureContext.replaceLoad,
        platform: PlayerFailurePlatform.android,
        itemId: 'track-2',
      );

      expect(failure, isNull);
    });

    test('does not expose stale load failures', () {
      final failure = mapper.map(
        StateError('unknown stale load failure'),
        context: PlayerFailureContext.staleLoad,
        platform: PlayerFailurePlatform.android,
        itemId: 'track-1',
      );

      expect(failure, isNull);
    });

    test('initial load failure keeps the pending target item id', () {
      final failure = mapper.map(
        PlayerException(0, 'network unavailable', 0),
        context: PlayerFailureContext.initialLoad,
        platform: PlayerFailurePlatform.android,
        itemId: 'initial-target',
      );

      expect(failure?.itemId, 'initial-target');
      expect(failure?.code, 'network');
    });

    test(
      'replace load failure targets B while active A stays outside mapper',
      () {
        final failure = mapper.map(
          PlayerException(0, 'network unavailable', 0),
          context: PlayerFailureContext.replaceLoad,
          platform: PlayerFailurePlatform.android,
          itemId: 'pending-b',
        );

        expect(failure?.itemId, 'pending-b');
        expect(failure?.code, 'network');
      },
    );

    test('maps Web MediaError network code with generic load message', () {
      final failure = mapper.map(
        PlatformException(code: '2', message: 'Failed to load URL'),
        context: PlayerFailureContext.initialLoad,
        platform: PlayerFailurePlatform.web,
        itemId: 'web-network',
      );

      expect(failure?.code, 'network');
      expect(failure?.isRecoverable, isTrue);
      expect(failure?.itemId, 'web-network');
    });

    test(
      'maps Web MediaError decode and source codes to unsupported format',
      () {
        for (final code in ['3', '4']) {
          final failure = mapper.map(
            PlatformException(code: code, message: 'Failed to load URL'),
            context: PlayerFailureContext.runtime,
            platform: PlayerFailurePlatform.web,
            itemId: 'web-format',
          );

          expect(failure?.code, 'unsupported_format');
          expect(failure?.isRecoverable, isFalse);
        }
      },
    );

    test('uses Web numeric category before a conflicting message keyword', () {
      final failure = mapper.map(
        PlatformException(code: '3', message: 'network failure'),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.web,
        itemId: 'web-decode',
      );

      expect(failure?.code, 'unsupported_format');
    });

    test('suppresses Web MediaError aborted code as an interrupted load', () {
      final failure = mapper.map(
        PlatformException(code: '1', message: 'Failed to load URL'),
        context: PlayerFailureContext.replaceLoad,
        platform: PlayerFailurePlatform.web,
        itemId: 'web-stale',
      );

      expect(failure, isNull);
    });

    test('maps Android source and Media3 error codes by Android origin', () {
      final sourceFailure = mapper.map(
        PlayerException(0, 'Failed to load URL', 0),
        context: PlayerFailureContext.initialLoad,
        platform: PlayerFailurePlatform.android,
        itemId: 'android-source',
      );
      final fileFailure = mapper.map(
        PlayerException(2005, 'Media source failed.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.android,
        itemId: 'android-file',
      );

      expect(sourceFailure?.code, 'network');
      expect(fileFailure?.code, 'not_found');
    });

    test('maps Apple network and format codes by Apple origin', () {
      final networkFailure = mapper.map(
        PlayerException(-1009, 'The operation could not be completed.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.apple,
        itemId: 'apple-network',
      );
      final formatFailure = mapper.map(
        PlayerException(-11828, 'The file format is not recognized.', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.apple,
        itemId: 'apple-format',
      );

      expect(networkFailure?.code, 'network');
      expect(formatFailure?.code, 'unsupported_format');
    });

    test('does not apply numeric mapping when platform origin is unknown', () {
      final failure = mapper.map(
        PlayerException(2, 'Failed to load URL', 0),
        context: PlayerFailureContext.runtime,
        platform: PlayerFailurePlatform.unknown,
        itemId: 'unknown-platform',
      );

      expect(failure?.code, 'unknown_engine');
    });
  });
}
