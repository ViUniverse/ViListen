// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

/// Immutable identity of one load or retry attempt.
///
/// [generation] implements latest-load-wins within one publication epoch.
/// [publicationEpoch] prevents events captured before a Stop barrier from
/// being published after that barrier has completed.
final class LoadGeneration {
  const LoadGeneration({
    required this.generation,
    required this.publicationEpoch,
  });

  final int generation;
  final int publicationEpoch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadGeneration &&
          other.generation == generation &&
          other.publicationEpoch == publicationEpoch;

  @override
  int get hashCode => Object.hash(generation, publicationEpoch);

  @override
  String toString() =>
      'LoadGeneration(generation: $generation, '
      'publicationEpoch: $publicationEpoch)';
}

/// Identity of an active Stop publication barrier.
final class PublicationBarrier {
  const PublicationBarrier({required this.epoch});

  final int epoch;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicationBarrier && other.epoch == epoch;

  @override
  int get hashCode => epoch.hashCode;

  @override
  String toString() => 'PublicationBarrier(epoch: $epoch)';
}

/// Protects load/retry results and serializes short command critical sections.
///
/// A new load/retry invalidates every earlier attempt immediately. The guard
/// deliberately does not await a load while holding the serialization tail:
/// stale loads must be allowed to finish without blocking a newer source.
/// Callers should use [runSerialized] only around command sections that are
/// safe to serialize, such as graph mutation or publication.
final class LoadGenerationGuard {
  int _nextGeneration = 0;
  int? _latestGeneration;
  int _publicationEpoch = 0;
  int? _activeBarrierEpoch;
  Future<void> _serializationTail = Future<void>.value();

  int? get latestGeneration => _latestGeneration;

  int get publicationEpoch => _publicationEpoch;

  bool get isStopping => _activeBarrierEpoch != null;

  /// Starts a new source load and invalidates any earlier load or retry.
  LoadGeneration beginLoad() {
    _ensureOutsideStopBarrier();

    final attempt = LoadGeneration(
      generation: ++_nextGeneration,
      publicationEpoch: _publicationEpoch,
    );
    _latestGeneration = attempt.generation;
    return attempt;
  }

  /// Starts a new retry transaction.
  LoadGeneration beginRetry() => beginLoad();

  /// Invalidates a pending load/retry when navigation changes the source.
  ///
  /// Navigation may not start a load itself, so it must not allocate a new
  /// generation. The next real load/retry will allocate the next generation.
  void invalidateForSourceNavigation() {
    _ensureOutsideStopBarrier();
    _latestGeneration = null;
  }

  /// Opens a Stop barrier and invalidates every pending load/retry.
  PublicationBarrier enterStop() {
    if (isStopping) {
      throw StateError('A Stop publication barrier is already active.');
    }

    final barrier = PublicationBarrier(epoch: ++_publicationEpoch);
    _latestGeneration = null;
    _activeBarrierEpoch = barrier.epoch;
    return barrier;
  }

  /// Closes [barrier]. A mismatched barrier cannot release the active one.
  void exitStop(PublicationBarrier barrier) {
    if (_activeBarrierEpoch != barrier.epoch) {
      throw StateError('The supplied Stop publication barrier is not active.');
    }

    _activeBarrierEpoch = null;
  }

  /// Runs [command] with a Stop barrier that is always released.
  ///
  /// This is intentionally not a replacement for the command coordinator.
  /// The coordinator decides when a source-changing command may start; this
  /// helper only guarantees barrier cleanup when the command throws.
  Future<T> runWithStopBarrier<T>(Future<T> Function() command) async {
    final barrier = enterStop();
    try {
      return await command();
    } finally {
      exitStop(barrier);
    }
  }

  /// Runs a short critical section after earlier sections in submission order.
  ///
  /// The tail Future never completes with an error. Therefore one throwing
  /// command cannot poison or deadlock commands submitted after it.
  Future<T> runSerialized<T>(Future<T> Function() command) {
    final predecessor = _serializationTail;
    final release = Completer<void>();
    _serializationTail = release.future;
    return _runAfter(predecessor, release, command);
  }

  /// Returns true only for an attempt that may still commit or publish.
  bool isCurrent(LoadGeneration attempt) =>
      !isStopping &&
      attempt.publicationEpoch == _publicationEpoch &&
      attempt.generation == _latestGeneration;

  /// Alias that reads naturally at publication call sites.
  bool canPublish(LoadGeneration attempt) => isCurrent(attempt);

  Future<T> _runAfter<T>(
    Future<void> predecessor,
    Completer<void> release,
    Future<T> Function() command,
  ) async {
    await predecessor;
    try {
      return await command();
    } finally {
      release.complete();
    }
  }

  void _ensureOutsideStopBarrier() {
    if (isStopping) {
      throw StateError('Cannot start a load while the Stop barrier is active.');
    }
  }
}
