// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/infrastructure/periodic_player_clock.dart';

void main() {
  test('requires a positive cadence', () {
    expect(
      () => PeriodicPlayerClock(cadence: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => PeriodicPlayerClock(cadence: const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
  });

  test('dispose is idempotent and closes the tick stream', () async {
    final clock = PeriodicPlayerClock();
    expect(clock.ticks.isBroadcast, isTrue);

    final firstDispose = clock.dispose();
    final secondDispose = clock.dispose();

    expect(identical(firstDispose, secondDispose), isTrue);
    await firstDispose;
    await expectLater(clock.ticks, emitsDone);
  });
}
