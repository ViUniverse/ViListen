// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';

void main() {
  group('PlayerCommandFailure', () {
    const failure = PlayerCommandFailure(
      code: 'invalidSpeed',
      message: 'Speed must be between 0.5 and 2.0.',
      command: 'setSpeed',
    );

    test('retains its code, message, and command', () {
      expect(failure.code, 'invalidSpeed');
      expect(failure.message, 'Speed must be between 0.5 and 2.0.');
      expect(failure.command, 'setSpeed');
    });

    test('uses all fields for equality and hashCode', () {
      const sameFailure = PlayerCommandFailure(
        code: 'invalidSpeed',
        message: 'Speed must be between 0.5 and 2.0.',
        command: 'setSpeed',
      );
      const differentCode = PlayerCommandFailure(
        code: 'commandUnavailable',
        message: 'Speed must be between 0.5 and 2.0.',
        command: 'setSpeed',
      );
      const differentMessage = PlayerCommandFailure(
        code: 'invalidSpeed',
        message: 'The speed is invalid.',
        command: 'setSpeed',
      );
      const differentCommand = PlayerCommandFailure(
        code: 'invalidSpeed',
        message: 'Speed must be between 0.5 and 2.0.',
        command: 'play',
      );

      expect(failure, sameFailure);
      expect(failure.hashCode, sameFailure.hashCode);
      expect(failure, isNot(differentCode));
      expect(failure, isNot(differentMessage));
      expect(failure, isNot(differentCommand));
    });

    test(
      'can complete a failed Future with the typed command failure',
      () async {
        await expectLater(
          _invalidCommandFuture(failure),
          throwsA(allOf(isA<PlayerCommandFailure>(), equals(failure))),
        );
      },
    );
  });
}

Future<void> _invalidCommandFuture(PlayerCommandFailure failure) =>
    Future<void>.error(failure);
