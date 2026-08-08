// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';

void main() {
  group('PlayerFailure', () {
    const failure = PlayerFailure(
      code: 'network',
      message: 'The audio source could not be loaded.',
      isRecoverable: true,
      itemId: 'track-1',
    );

    test('retains its fields', () {
      expect(failure.code, 'network');
      expect(failure.message, 'The audio source could not be loaded.');
      expect(failure.isRecoverable, isTrue);
      expect(failure.itemId, 'track-1');
    });

    test('uses all fields for equality and hashCode', () {
      const sameFailure = PlayerFailure(
        code: 'network',
        message: 'The audio source could not be loaded.',
        isRecoverable: true,
        itemId: 'track-1',
      );
      const differentCode = PlayerFailure(
        code: 'not_found',
        message: 'The audio source could not be loaded.',
        isRecoverable: true,
        itemId: 'track-1',
      );
      const differentMessage = PlayerFailure(
        code: 'network',
        message: 'The source is unavailable.',
        isRecoverable: true,
        itemId: 'track-1',
      );
      const differentRecoverability = PlayerFailure(
        code: 'network',
        message: 'The audio source could not be loaded.',
        isRecoverable: false,
        itemId: 'track-1',
      );
      const differentItem = PlayerFailure(
        code: 'network',
        message: 'The audio source could not be loaded.',
        isRecoverable: true,
        itemId: 'track-2',
      );

      expect(failure, sameFailure);
      expect(failure.hashCode, sameFailure.hashCode);
      expect(failure, isNot(differentCode));
      expect(failure, isNot(differentMessage));
      expect(failure, isNot(differentRecoverability));
      expect(failure, isNot(differentItem));
    });

    test('copyWith updates fields without mutating the original', () {
      final copy = failure.copyWith(
        code: 'not_found',
        message: 'The source is unavailable.',
        isRecoverable: false,
        itemId: 'track-2',
      );

      expect(copy.code, 'not_found');
      expect(copy.message, 'The source is unavailable.');
      expect(copy.isRecoverable, isFalse);
      expect(copy.itemId, 'track-2');
      expect(
        failure,
        const PlayerFailure(
          code: 'network',
          message: 'The audio source could not be loaded.',
          isRecoverable: true,
          itemId: 'track-1',
        ),
      );
    });

    test('copyWith can clear itemId', () {
      expect(failure.copyWith(itemId: null).itemId, isNull);
    });

    test('is a domain value and does not carry exception metadata', () {
      expect(failure, isNot(isA<Exception>()));
    });
  });
}
