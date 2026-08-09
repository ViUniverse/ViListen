// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/infrastructure/load_generation_guard.dart';

void main() {
  late LoadGenerationGuard guard;

  setUp(() {
    guard = LoadGenerationGuard();
  });

  test('assigns increasing generations to load and retry attempts', () {
    final load = guard.beginLoad();
    final retry = guard.beginRetry();

    expect(load.generation, 1);
    expect(retry.generation, 2);
    expect(load.publicationEpoch, 0);
    expect(retry.publicationEpoch, 0);
    expect(guard.latestGeneration, 2);
    expect(guard.isCurrent(load), isFalse);
    expect(guard.isCurrent(retry), isTrue);
  });

  test('late success from A is stale after source B starts', () async {
    final aCompleter = Completer<String>();
    final bCompleter = Completer<String>();
    final published = <String>[];
    final a = guard.beginLoad();

    final aObservation = _observeSuccess(
      aCompleter.future,
      () => guard.isCurrent(a),
      published,
      'A',
    );
    final b = guard.beginLoad();
    final bObservation = _observeSuccess(
      bCompleter.future,
      () => guard.isCurrent(b),
      published,
      'B',
    );

    aCompleter.complete('A');
    bCompleter.complete('B');
    await Future.wait([aObservation, bObservation]);

    expect(published, ['B']);
    expect(guard.canPublish(a), isFalse);
    expect(guard.canPublish(b), isTrue);
  });

  test('late error from A is stale after source B starts', () async {
    final aCompleter = Completer<void>();
    final bCompleter = Completer<void>();
    final failures = <String>[];
    final a = guard.beginLoad();

    final aObservation = _observeError(
      aCompleter.future,
      () => guard.isCurrent(a),
      failures,
      'A',
    );
    final b = guard.beginLoad();
    final bObservation = _observeError(
      bCompleter.future,
      () => guard.isCurrent(b),
      failures,
      'B',
    );

    aCompleter.completeError(StateError('late A failure'));
    bCompleter.completeError(StateError('current B failure'));
    await Future.wait([aObservation, bObservation]);

    expect(failures, ['B']);
    expect(guard.isCurrent(a), isFalse);
    expect(guard.isCurrent(b), isTrue);
  });

  test(
    'Stop invalidates a pending load before the command completes',
    () async {
      final a = guard.beginLoad();
      final stopCompleter = Completer<void>();
      final stop = guard.runWithStopBarrier(() => stopCompleter.future);

      expect(guard.isStopping, isTrue);
      expect(guard.isCurrent(a), isFalse);
      expect(guard.publicationEpoch, 1);
      expect(() => guard.beginLoad(), throwsStateError);

      stopCompleter.complete();
      await stop;

      expect(guard.isStopping, isFalse);
      expect(guard.isCurrent(a), isFalse);

      final afterStop = guard.beginLoad();
      expect(afterStop.generation, 2);
      expect(afterStop.publicationEpoch, 1);
      expect(guard.isCurrent(afterStop), isTrue);
    },
  );

  test('a new source invalidates a pending retry', () {
    final retry = guard.beginRetry();
    final item = guard.beginLoad();

    expect(guard.isCurrent(retry), isFalse);
    expect(guard.isCurrent(item), isTrue);
    expect(item.generation, retry.generation + 1);
  });

  test('source navigation invalidates a pending load', () {
    final load = guard.beginLoad();

    guard.invalidateForSourceNavigation();

    expect(guard.latestGeneration, isNull);
    expect(guard.isCurrent(load), isFalse);
  });

  test('source navigation invalidates a pending retry', () {
    final retry = guard.beginRetry();

    guard.invalidateForSourceNavigation();

    expect(guard.latestGeneration, isNull);
    expect(guard.isCurrent(retry), isFalse);
  });

  test(
    'Stop keeps pre-barrier events stale after the barrier closes',
    () async {
      final beforeStop = guard.beginLoad();
      final barrier = guard.enterStop();

      expect(guard.isCurrent(beforeStop), isFalse);
      guard.exitStop(barrier);

      expect(guard.isCurrent(beforeStop), isFalse);
      expect(guard.publicationEpoch, barrier.epoch);
    },
  );

  test(
    'a throwing serialized command does not block the next command',
    () async {
      final failure = StateError('command failed');
      var secondCommandRan = false;

      await expectLater(
        guard.runSerialized<void>(() => Future<void>.error(failure)),
        throwsA(same(failure)),
      );
      await guard.runSerialized<void>(() async {
        secondCommandRan = true;
      });

      expect(secondCommandRan, isTrue);
    },
  );

  test('a throwing Stop command releases the publication barrier', () async {
    final failure = StateError('stop failed');

    await expectLater(
      guard.runWithStopBarrier<void>(() => Future<void>.error(failure)),
      throwsA(same(failure)),
    );

    expect(guard.isStopping, isFalse);
    final nextLoad = guard.beginLoad();
    expect(guard.isCurrent(nextLoad), isTrue);
  });

  test('serialized commands execute in submission order', () async {
    final first = Completer<void>();
    final events = <String>[];

    final firstCommand = guard.runSerialized<void>(() async {
      events.add('first-start');
      await first.future;
      events.add('first-end');
    });
    final secondCommand = guard.runSerialized<void>(() async {
      events.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);

    first.complete();
    await Future.wait([firstCommand, secondCommand]);
    expect(events, ['first-start', 'first-end', 'second']);
  });
}

Future<void> _observeSuccess(
  Future<String> result,
  bool Function() isCurrent,
  List<String> published,
  String label,
) async {
  await result;
  if (isCurrent()) {
    published.add(label);
  }
}

Future<void> _observeError(
  Future<void> result,
  bool Function() isCurrent,
  List<String> failures,
  String label,
) async {
  try {
    await result;
  } catch (_) {
    if (isCurrent()) {
      failures.add(label);
    }
  }
}
