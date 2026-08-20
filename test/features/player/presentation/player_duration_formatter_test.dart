// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/presentation/player_duration_formatter.dart';

void main() {
  group('formatElapsed', () {
    final cases = <(Duration, String)>[
      (Duration.zero, '0:00'),
      (const Duration(milliseconds: -500), '0:00'),
      (const Duration(seconds: 7), '0:07'),
      (const Duration(minutes: 12, seconds: 34), '12:34'),
      (const Duration(seconds: 160), '2:40'),
      (const Duration(minutes: 59, seconds: 59), '59:59'),
      (const Duration(hours: 1, minutes: 2, seconds: 3), '1:02:03'),
    ];

    for (final (input, expected) in cases) {
      test('$input -> $expected', () {
        expect(formatElapsed(input), expected);
      });
    }
  });

  group('formatRemaining', () {
    test('formats a positive duration with a minus prefix', () {
      expect(formatRemaining(const Duration(minutes: 2, seconds: 40)), '-2:40');
    });

    test('formats zero as negative zero', () {
      expect(formatRemaining(Duration.zero), '-0:00');
    });

    test('clamps a negative duration to negative zero', () {
      expect(formatRemaining(const Duration(seconds: -7)), '-0:00');
    });
  });
}
