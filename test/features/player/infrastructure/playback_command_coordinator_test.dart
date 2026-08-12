// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/infrastructure/load_generation_guard.dart';
import 'package:vi_listen/features/player/infrastructure/playback_command_coordinator.dart';

void main() {
  late PlaybackCommandCoordinator coordinator;
  late _ControlledPlatform platform;

  setUp(() {
    coordinator = PlaybackCommandCoordinator();
    platform = _ControlledPlatform();
  });

  test('coalesces two pending Play calls', () async {
    final first = coordinator.setDesiredPlaying(
      true,
      () => platform.invoke('play'),
    );
    await _flush();

    final second = coordinator.setDesiredPlaying(
      true,
      () => platform.invoke('play'),
    );

    expect(platform.calls, ['play']);
    expect(identical(first, second), isTrue);

    platform.complete('play');
    await Future.wait([first, second]);
    expect(platform.calls, ['play']);
  });

  test('coalesces two pending Pause calls', () async {
    final first = coordinator.setDesiredPlaying(
      false,
      () => platform.invoke('pause'),
    );
    await _flush();

    final second = coordinator.setDesiredPlaying(
      false,
      () => platform.invoke('pause'),
    );

    expect(platform.calls, ['pause']);
    expect(identical(first, second), isTrue);

    platform.complete('pause');
    await Future.wait([first, second]);
    expect(platform.calls, ['pause']);
  });

  test(
    'runs Pause after a pending Play when the last intent is Pause',
    () async {
      final play = coordinator.setDesiredPlaying(
        true,
        () => platform.invoke('play'),
      );
      await _flush();

      final pause = coordinator.setDesiredPlaying(
        false,
        () => platform.invoke('pause'),
      );

      expect(platform.calls, ['play']);
      platform.complete('play');
      await _flush();
      expect(platform.calls, ['play', 'pause']);

      platform.complete('pause');
      await Future.wait([play, pause]);
    },
  );

  test(
    'runs Play after a pending Pause when the last intent is Play',
    () async {
      final pause = coordinator.setDesiredPlaying(
        false,
        () => platform.invoke('pause'),
      );
      await _flush();

      final play = coordinator.setDesiredPlaying(
        true,
        () => platform.invoke('play'),
      );

      expect(platform.calls, ['pause']);
      platform.complete('pause');
      await _flush();
      expect(platform.calls, ['pause', 'play']);

      platform.complete('play');
      await Future.wait([pause, play]);
    },
  );

  test('a newer rapid intent supersedes an opposite pending intent', () async {
    final play = coordinator.setDesiredPlaying(
      true,
      () => platform.invoke('play'),
    );
    await _flush();

    final pause = coordinator.setDesiredPlaying(
      false,
      () => platform.invoke('pause'),
    );
    final playAgain = coordinator.setDesiredPlaying(
      true,
      () => platform.invoke('play'),
    );

    expect(platform.calls, ['play']);
    expect(identical(play, playAgain), isTrue);

    platform.complete('play');
    await Future.wait([play, pause, playAgain]);
    expect(platform.calls, ['play']);
  });

  test('a failed Play does not block the next desired intent', () async {
    final failure = StateError('play rejected');
    final play = coordinator.setDesiredPlaying(
      true,
      () => platform.invoke('play', error: failure),
    );
    await _flush();

    final pause = coordinator.setDesiredPlaying(
      false,
      () => platform.invoke('pause'),
    );

    platform.complete('play');
    await expectLater(play, throwsA(same(failure)));
    await _flush();
    expect(platform.calls, ['play', 'pause']);

    platform.complete('pause');
    await pause;
  });

  test(
    'dispatches Pause while a just_audio-style Play Future is pending',
    () async {
      final playCompletion = Completer<void>();
      final pauseCompletion = Completer<void>();
      var pauseDispatched = false;

      final play = coordinator.setDesiredPlaying(
        true,
        () => playCompletion.future,
      );
      await _flush();

      final pause = coordinator.setDesiredPlaying(false, () {
        pauseDispatched = true;
        if (!playCompletion.isCompleted) {
          playCompletion.complete();
        }
        return pauseCompletion.future;
      });
      await _flush();

      // The completers model the engine's two lifetime Futures. Reaching this
      // point proves the opposite command was dispatched rather than waiting
      // for Play completion.
      expect(pauseDispatched, isTrue);
      expect(pauseCompletion.isCompleted, isFalse);

      pauseCompletion.complete();
      await Future.wait<void>([play, pause]);
    },
  );

  test(
    'load graph mutations are serialized behind an interrupt handshake',
    () async {
      late LoadGeneration firstGeneration;
      late LoadGeneration secondGeneration;
      final first = coordinator.load((generation) async {
        firstGeneration = generation;
        await platform.invoke('load-a');
      }, interrupt: () => platform.invoke('interrupt-a'));
      await _flush();

      final second = coordinator.load((generation) async {
        secondGeneration = generation;
        await platform.invoke('load-b');
      }, interrupt: () => platform.invoke('interrupt-b'));
      await _flush();

      expect(platform.calls, ['load-a', 'interrupt-a']);
      expect(platform.calls, isNot(contains('load-b')));

      platform.complete('interrupt-a');
      await _flush();
      expect(platform.calls, isNot(contains('load-b')));

      platform.complete('load-a');
      await first;
      await _flush();
      expect(platform.calls, ['load-a', 'interrupt-a', 'load-b']);

      platform.complete('load-b');
      await second;
      expect(coordinator.isCurrent(secondGeneration), isTrue);
      expect(coordinator.isCurrent(firstGeneration), isFalse);
    },
  );

  test(
    'keeps the graph lane when load completes before its interrupt handshake',
    () async {
      final first = coordinator.load(
        (_) => platform.invoke('load-a'),
        interrupt: () => platform.invoke('interrupt-a'),
      );
      await _flush();

      final second = coordinator.load(
        (_) => platform.invoke('load-b'),
        interrupt: () => platform.invoke('interrupt-b'),
      );
      await _flush();

      expect(platform.calls, ['load-a', 'interrupt-a']);

      platform.complete('load-a');
      await _flush();
      expect(platform.calls, ['load-a', 'interrupt-a']);

      platform.complete('interrupt-a');
      await first;
      await _flush();
      expect(platform.calls, ['load-a', 'interrupt-a', 'load-b']);

      platform.complete('load-b');
      await second;
    },
  );

  test(
    'a retry for the same target coalesces and a new target waits safely',
    () async {
      late LoadGeneration firstGeneration;
      late LoadGeneration secondGeneration;
      final first = coordinator.retry('track-a', (generation) async {
        firstGeneration = generation;
        await platform.invoke('retry-a');
      }, interrupt: () => platform.invoke('interrupt-retry-a'));
      await _flush();

      final sameTarget = coordinator.retry(
        'track-a',
        (_) => fail('same retry target must be coalesced'),
      );
      expect(identical(first, sameTarget), isTrue);

      final second = coordinator.retry('track-b', (generation) async {
        secondGeneration = generation;
        await platform.invoke('retry-b');
      }, interrupt: () => platform.invoke('interrupt-retry-b'));
      await _flush();

      expect(platform.calls, ['retry-a', 'interrupt-retry-a']);
      platform.complete('interrupt-retry-a');
      platform.complete('retry-a');
      await first;
      await sameTarget;
      await _flush();
      expect(platform.calls, ['retry-a', 'interrupt-retry-a', 'retry-b']);

      platform.complete('retry-b');
      await second;
      expect(coordinator.isCurrent(secondGeneration), isTrue);
      expect(coordinator.isCurrent(firstGeneration), isFalse);
    },
  );

  test('Stop never overlaps a pending load graph mutation', () async {
    late LoadGeneration loadGeneration;
    final load = coordinator.load((generation) async {
      loadGeneration = generation;
      await platform.invoke('load');
    }, interrupt: () => platform.invoke('interrupt-load'));
    await _flush();

    final stop = coordinator.stop((barrier) async {
      expect(coordinator.isStopping, isTrue);
      expect(barrier.epoch, 1);
      await platform.invoke('stop');
    });
    await _flush();

    expect(platform.calls, ['load', 'interrupt-load']);
    expect(platform.calls, isNot(contains('stop')));

    platform.complete('interrupt-load');
    await _flush();
    expect(platform.calls, isNot(contains('stop')));

    platform.complete('load');
    await load;
    await _flush();
    expect(platform.calls, ['load', 'interrupt-load', 'stop']);

    platform.complete('stop');
    await stop;
    expect(coordinator.isStopping, isFalse);
    expect(coordinator.isCurrent(loadGeneration), isFalse);
  });

  test('a queued Stop cannot be canceled by a later load', () async {
    final first = coordinator.load(
      (_) => platform.invoke('load-a'),
      interrupt: () => platform.invoke('interrupt-a'),
    );
    await _flush();

    final stop = coordinator.stop((_) => platform.invoke('stop'));
    await _flush();

    final second = coordinator.load((_) => platform.invoke('load-b'));
    await _flush();

    expect(coordinator.isStopping, isTrue);
    expect(platform.calls, ['load-a', 'interrupt-a']);

    platform.complete('interrupt-a');
    platform.complete('load-a');
    await first;
    await _flush();
    expect(platform.calls, ['load-a', 'interrupt-a', 'stop']);
    expect(coordinator.isStopping, isTrue);
    expect(platform.calls, isNot(contains('load-b')));

    platform.complete('stop');
    await stop;
    await _flush();
    expect(coordinator.isStopping, isFalse);
    expect(platform.calls, ['load-a', 'interrupt-a', 'stop', 'load-b']);

    platform.complete('load-b');
    await second;
  });

  test('Next and Stop do not overlap an index-switch graph mutation', () async {
    final retry = coordinator.retry(
      'track-a',
      (_) async => platform.invoke('retry'),
      interrupt: () => platform.invoke('interrupt-retry'),
    );
    await _flush();

    final next = coordinator.switchSourceIndex(
      () => platform.invoke('next'),
      interrupt: () => platform.invoke('interrupt-next'),
    );
    await _flush();
    expect(platform.calls, ['retry', 'interrupt-retry']);

    platform.complete('interrupt-retry');
    platform.complete('retry');
    await retry;
    await _flush();
    expect(platform.calls, ['retry', 'interrupt-retry', 'next']);

    final stop = coordinator.stop((_) => platform.invoke('stop'));
    await _flush();
    expect(platform.calls, [
      'retry',
      'interrupt-retry',
      'next',
      'interrupt-next',
    ]);
    expect(platform.calls, isNot(contains('stop')));

    platform.complete('interrupt-next');
    platform.complete('next');
    await next;
    await _flush();
    expect(platform.calls, [
      'retry',
      'interrupt-retry',
      'next',
      'interrupt-next',
      'stop',
    ]);

    platform.complete('stop');
    await stop;
  });

  test('a throwing graph transaction releases the lane', () async {
    final failure = StateError('load failed');
    final first = coordinator.load((_) async {
      await platform.invoke('load-a');
      throw failure;
    }, interrupt: () => platform.invoke('interrupt-a'));
    await _flush();

    final second = coordinator.load((_) async {
      await platform.invoke('load-b');
    }, interrupt: () => platform.invoke('interrupt-b'));
    await _flush();

    platform.complete('interrupt-a');
    platform.complete('load-a');
    await expectLater(first, throwsA(same(failure)));
    await _flush();
    expect(platform.calls, ['load-a', 'interrupt-a', 'load-b']);

    platform.complete('load-b');
    await second;
  });

  test('position work is independent from the graph lane', () async {
    var positionEvents = 0;
    final load = coordinator.load(
      (_) async => platform.invoke('load'),
      interrupt: () => platform.invoke('interrupt-load'),
    );
    await _flush();

    positionEvents += 1;
    expect(positionEvents, 1);

    platform.complete('load');
    await load;
  });

  test('source tokens invalidate before source mutations run', () async {
    final beforeLoad = coordinator.captureSourceToken();
    final load = coordinator.load((_) async {
      expect(coordinator.isSourceTokenCurrent(beforeLoad), isFalse);
    });
    await load;

    final beforeNavigation = coordinator.captureSourceToken();
    expect(coordinator.isSourceTokenCurrent(beforeNavigation), isTrue);
    final navigation = coordinator.switchSourceIndex(() async {
      expect(coordinator.isSourceTokenCurrent(beforeNavigation), isFalse);
    });
    await navigation;

    final beforeStop = coordinator.captureSourceToken();
    expect(coordinator.isSourceTokenCurrent(beforeStop), isTrue);
    final stop = coordinator.stop((_) async {
      expect(coordinator.isSourceTokenCurrent(beforeStop), isFalse);
    });
    await stop;
    expect(coordinator.isSourceTokenCurrent(beforeStop), isFalse);
  });

  test(
    'a Stop failure releases the barrier for the next graph command',
    () async {
      final failure = StateError('stop rejected');
      final stop = coordinator.stop(
        (_) async => platform.invoke('stop', error: failure),
      );
      await _flush();

      platform.complete('stop');
      await expectLater(stop, throwsA(same(failure)));
      expect(coordinator.isStopping, isFalse);

      final load = coordinator.load((generation) async {
        expect(coordinator.isCurrent(generation), isTrue);
      });
      await load;
    },
  );
}

final class _ControlledPlatform {
  final List<String> calls = <String>[];
  final Map<String, Completer<void>> _pending = <String, Completer<void>>{};
  final Map<String, Object> _errors = <String, Object>{};

  Future<void> invoke(String name, {Object? error}) {
    calls.add(name);
    final completer = Completer<void>();
    _pending[name] = completer;
    if (error != null) {
      _errors[name] = error;
    }
    return completer.future;
  }

  void complete(String name) {
    final completer = _pending.remove(name);
    if (completer == null) {
      throw StateError('No pending platform call named $name.');
    }

    final error = _errors.remove(name);
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete();
    }
  }
}

Future<void> _flush() async {
  await Future<void>.microtask(() {});
  await Future<void>.delayed(Duration.zero);
}
