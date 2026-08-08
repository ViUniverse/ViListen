// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/infrastructure/playback_position_policy.dart';

void main() {
  group('PlaybackPositionPolicy', () {
    test('returns unavailable when duration is zero or negative', () {
      expect(
        PlaybackPositionPolicy.clampSeek(
          target: const Duration(seconds: 5),
          duration: Duration.zero,
        ),
        isNull,
      );
      expect(
        PlaybackPositionPolicy.clampSeek(
          target: const Duration(seconds: 5),
          duration: const Duration(seconds: -1),
        ),
        isNull,
      );
    });

    test('clamps seek target to the inclusive duration range', () {
      const duration = Duration(seconds: 60);

      expect(
        PlaybackPositionPolicy.clampSeek(
          target: const Duration(seconds: -5),
          duration: duration,
        ),
        Duration.zero,
      );
      expect(
        PlaybackPositionPolicy.clampSeek(
          target: const Duration(seconds: 15),
          duration: duration,
        ),
        const Duration(seconds: 15),
      );
      expect(
        PlaybackPositionPolicy.clampSeek(target: duration, duration: duration),
        duration,
      );
      expect(
        PlaybackPositionPolicy.clampSeek(
          target: const Duration(seconds: 65),
          duration: duration,
        ),
        duration,
      );
    });

    test('computes and clamps skip target using the supplied offset', () {
      const duration = Duration(seconds: 60);

      expect(
        PlaybackPositionPolicy.skipTarget(
          position: const Duration(seconds: 20),
          offset: const Duration(seconds: -10),
          duration: duration,
        ),
        const Duration(seconds: 10),
      );
      expect(
        PlaybackPositionPolicy.skipTarget(
          position: const Duration(seconds: 5),
          offset: const Duration(seconds: -10),
          duration: duration,
        ),
        Duration.zero,
      );
      expect(
        PlaybackPositionPolicy.skipTarget(
          position: const Duration(seconds: 55),
          offset: const Duration(seconds: 10),
          duration: duration,
        ),
        duration,
      );
    });

    test('returns unavailable for skip when duration is unknown', () {
      expect(
        PlaybackPositionPolicy.skipTarget(
          position: const Duration(seconds: 5),
          offset: const Duration(seconds: 10),
          duration: Duration.zero,
        ),
        isNull,
      );
    });

    test(
      'restarts the current item when position is greater than three seconds',
      () {
        final decision = PlaybackPositionPolicy.previous(
          position: const Duration(seconds: 4),
          currentIndex: 1,
          queueLength: 3,
        );

        expect(decision.kind, PreviousDecisionKind.restartCurrent);
        expect(decision.targetIndex, isNull);
      },
    );

    test('navigates to the previous index at exactly three seconds', () {
      final decision = PlaybackPositionPolicy.previous(
        position: const Duration(seconds: 3),
        currentIndex: 2,
        queueLength: 3,
      );

      expect(decision.kind, PreviousDecisionKind.navigateToIndex);
      expect(decision.targetIndex, 1);
    });

    test('navigates to the previous index below three seconds', () {
      final decision = PlaybackPositionPolicy.previous(
        position: const Duration(seconds: 2),
        currentIndex: 2,
        queueLength: 3,
      );

      expect(decision.kind, PreviousDecisionKind.navigateToIndex);
      expect(decision.targetIndex, 1);
    });

    test('returns no-op at the first queue index', () {
      final decision = PlaybackPositionPolicy.previous(
        position: const Duration(seconds: 3),
        currentIndex: 0,
        queueLength: 3,
      );

      expect(decision.kind, PreviousDecisionKind.noOp);
      expect(decision.targetIndex, isNull);
    });

    test('returns no-op for null, negative, or out-of-range queue index', () {
      for (final currentIndex in <int?>[null, -1, 3]) {
        final decision = PlaybackPositionPolicy.previous(
          position: const Duration(seconds: 2),
          currentIndex: currentIndex,
          queueLength: 3,
        );

        expect(decision.kind, PreviousDecisionKind.noOp);
        expect(decision.targetIndex, isNull);
      }
    });
  });
}
