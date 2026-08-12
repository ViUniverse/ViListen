// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'load_generation_guard.dart';

typedef PlaybackSourceTransaction =
    Future<void> Function(LoadGeneration generation);

typedef PlaybackStopTransaction =
    Future<void> Function(PublicationBarrier barrier);

typedef PlaybackCommandCall = Future<void> Function();

/// Identity of the source context observed by a Play/Pause transaction.
///
/// Source-changing commands invalidate this token before they wait on the
/// graph lane. This lets an in-flight transaction abandon its continuation
/// after an awaited engine call without allowing it to touch the replacement
/// source.
final class PlaybackSourceToken {
  const PlaybackSourceToken(this.revision);

  final int revision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSourceToken && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;

  @override
  String toString() => 'PlaybackSourceToken(revision: $revision)';
}

/// Coordinates mutations of the platform playback graph.
///
/// Every load, retry, Stop and source-index switch owns the graph lane until
/// its platform transaction completes. A newer source request invalidates its
/// generation immediately, then uses the older transaction's explicit
/// interrupt handshake before the lane can advance. Without an interrupt
/// handshake the newer request remains serialized behind the older Future.
///
/// Position events are not submitted to this class and therefore never wait on
/// the graph lane.
final class PlaybackCommandCoordinator {
  PlaybackCommandCoordinator({LoadGenerationGuard? generationGuard})
    : _generationGuard = generationGuard ?? LoadGenerationGuard();

  final LoadGenerationGuard _generationGuard;
  int _sourceRevision = 0;
  Future<void> _graphTail = Future<void>.value();
  _GraphRequest? _activeGraphRequest;
  _GraphRequest? _lastGraphRequest;

  _PlayPauseBatch? _inFlightPlayPause;
  _PlayPauseBatch? _pendingPlayPause;
  bool _drainingPlayPause = false;

  _RetryFlight? _retryFlight;

  bool get isStopping => _generationGuard.isStopping;

  int get publicationEpoch => _generationGuard.publicationEpoch;

  bool isCurrent(LoadGeneration generation) =>
      _generationGuard.isCurrent(generation);

  /// Captures the source context for a transaction that may await the engine.
  PlaybackSourceToken captureSourceToken() =>
      PlaybackSourceToken(_sourceRevision);

  /// Returns whether [token] may still continue against the current source.
  bool isSourceTokenCurrent(PlaybackSourceToken token) =>
      !_generationGuard.isStopping && token.revision == _sourceRevision;

  /// Serializes a source load for the full platform graph transaction.
  ///
  /// The generation is allocated immediately when no Stop barrier is active,
  /// so a newer request invalidates an older attempt before waiting for the
  /// graph lane. If the lane is currently in Stop, generation allocation is
  /// deferred until Stop releases the barrier.
  Future<void> load(
    PlaybackSourceTransaction transaction, {
    PlaybackCommandCall? interrupt,
  }) {
    _invalidateSourceDependentCommands();
    _invalidateSourceContext();

    final generation = _generationGuard.isStopping
        ? null
        : _generationGuard.beginLoad();
    return _enqueueGraph(() async {
      final attempt = generation ?? _generationGuard.beginLoad();
      await transaction(attempt);
    }, interrupt: interrupt);
  }

  /// Serializes a retry and coalesces a retry for the same target.
  ///
  /// A different [targetKey] invalidates the current retry generation and is
  /// queued behind the active graph transaction. [interrupt] is the explicit
  /// platform handshake used to stop the older retry/load before the next
  /// graph mutation starts.
  Future<void> retry(
    Object targetKey,
    PlaybackSourceTransaction transaction, {
    PlaybackCommandCall? interrupt,
  }) {
    final current = _retryFlight;
    if (current != null && current.targetKey == targetKey) {
      return current.future;
    }

    _invalidatePlayPauseIntent();
    _invalidateSourceContext();
    final generation = _generationGuard.isStopping
        ? null
        : _generationGuard.beginRetry();
    final future = _enqueueGraph(() async {
      final attempt = generation ?? _generationGuard.beginRetry();
      await transaction(attempt);
    }, interrupt: interrupt);
    _retryFlight = _RetryFlight(targetKey: targetKey, future: future);
    unawaited(
      future.then<void>(
        (_) => _clearRetryFlight(future),
        onError: (Object _, StackTrace _) => _clearRetryFlight(future),
      ),
    );
    return future;
  }

  /// Serializes the canonical Stop transaction.
  ///
  /// Stop enters its publication barrier immediately, invalidating older
  /// source attempts. The engine Stop call itself waits for the active graph
  /// transaction and its interrupt handshake; no graph mutations overlap.
  Future<void> stop(PlaybackStopTransaction transaction) {
    _invalidateSourceDependentCommands();
    _invalidateSourceContext();
    final barrier = _generationGuard.enterStop();
    return _enqueueGraph(() async {
      try {
        await transaction(barrier);
      } finally {
        _generationGuard.exitStop(barrier);
      }
    }, interruptible: false);
  }

  /// Serializes an explicit Next/Previous source-index switch.
  ///
  /// Navigation invalidates a pending load/retry before its graph transaction
  /// is queued. Boundary validation remains outside this coordinator; a
  /// boundary callback can complete successfully without a platform call.
  Future<void> switchSourceIndex(
    PlaybackCommandCall transaction, {
    PlaybackCommandCall? interrupt,
  }) {
    _invalidateSourceDependentCommands();
    _invalidateSourceContext();
    if (_generationGuard.isStopping) {
      return _enqueueGraph(() async {
        _generationGuard.invalidateForSourceNavigation();
        await transaction();
      }, interrupt: interrupt);
    }

    _generationGuard.invalidateForSourceNavigation();
    return _enqueueGraph(transaction, interrupt: interrupt);
  }

  /// Submits a desired Play/Pause intent.
  ///
  /// Equal intents join the in-flight/pending batch. An opposite intent waits
  /// for the in-flight platform call and becomes the next call. If it is
  /// replaced before execution, it is completed as an idempotent no-op.
  Future<void> setDesiredPlaying(
    bool desired,
    PlaybackCommandCall platformCall,
  ) {
    final inFlight = _inFlightPlayPause;
    final pending = _pendingPlayPause;

    if (pending != null && pending.desired == desired) {
      return pending.future;
    }

    if (pending != null) {
      _pendingPlayPause = null;
      pending.completeSuccess();
    }

    if (inFlight != null && inFlight.desired == desired) {
      return inFlight.future;
    }

    final batch = _PlayPauseBatch(desired: desired, platformCall: platformCall);
    if (inFlight == null) {
      _inFlightPlayPause = batch;
    } else {
      _pendingPlayPause = batch;
    }

    _ensurePlayPauseDrain();
    return batch.future;
  }

  /// Invalidates pending Play/Pause and retry continuations.
  ///
  /// The active platform Future is not force-cancelled here. Graph commands
  /// use their explicit [interrupt] handshake; this method only prevents a
  /// superseded Play/Pause follow-up from being scheduled.
  void invalidateSourceDependentCommands() {
    _invalidateSourceDependentCommands();
  }

  Future<void> _enqueueGraph(
    PlaybackCommandCall transaction, {
    PlaybackCommandCall? interrupt,
    bool interruptible = true,
  }) {
    _interruptOrCancelPendingGraphRequest();

    final predecessor = _graphTail;
    final release = Completer<void>();
    final request = _GraphRequest(
      transaction: transaction,
      interrupt: interrupt ?? _noOp,
      interruptible: interruptible,
    );
    _lastGraphRequest = request;
    _graphTail = release.future;

    return _runGraphRequest(predecessor, release, request);
  }

  Future<void> _runGraphRequest(
    Future<void> predecessor,
    Completer<void> release,
    _GraphRequest request,
  ) async {
    await predecessor;
    request.started = true;

    if (request.cancelledBeforeStart) {
      request.completed = true;
      release.complete();
      _clearLastGraphRequest(request);
      return;
    }

    _activeGraphRequest = request;
    try {
      final operation = request.startTransaction();
      await request.awaitCompletion(operation);
    } finally {
      request.completed = true;
      if (identical(_activeGraphRequest, request)) {
        _activeGraphRequest = null;
      }
      release.complete();
      _clearLastGraphRequest(request);
    }
  }

  void _interruptOrCancelPendingGraphRequest() {
    final active = _activeGraphRequest;
    if (active != null && active.interruptible) {
      unawaited(active.requestInterrupt());
    }

    final last = _lastGraphRequest;
    if (last == null || identical(last, active) || last.completed) {
      return;
    }

    if (!last.started && last.interruptible) {
      last.cancelBeforeStart();
    } else if (last.interruptible) {
      unawaited(last.requestInterrupt());
    }
  }

  void _invalidateSourceDependentCommands() {
    _retryFlight = null;
    _invalidatePlayPauseIntent();
  }

  void _invalidateSourceContext() {
    _sourceRevision += 1;
  }

  void _invalidatePlayPauseIntent() {
    final pending = _pendingPlayPause;
    _pendingPlayPause = null;
    pending?.completeSuccess();
  }

  void _clearLastGraphRequest(_GraphRequest request) {
    if (identical(_lastGraphRequest, request)) {
      _lastGraphRequest = null;
    }
  }

  void _clearRetryFlight(Future<void> future) {
    if (identical(_retryFlight?.future, future)) {
      _retryFlight = null;
    }
  }

  void _ensurePlayPauseDrain() {
    if (_drainingPlayPause) {
      return;
    }

    _drainingPlayPause = true;
    unawaited(_drainPlayPause());
  }

  Future<void> _drainPlayPause() async {
    while (true) {
      final batch = _inFlightPlayPause;
      if (batch == null) {
        _drainingPlayPause = false;
        return;
      }

      try {
        await batch.platformCall();
        batch.completeSuccess();
      } catch (error, stackTrace) {
        batch.completeError(error, stackTrace);
      }

      _inFlightPlayPause = null;
      final next = _pendingPlayPause;
      _pendingPlayPause = null;
      if (next == null) {
        _drainingPlayPause = false;
        return;
      }

      _inFlightPlayPause = next;
    }
  }
}

Future<void> _noOp() async {}

final class _GraphRequest {
  _GraphRequest({
    required this.transaction,
    required this.interrupt,
    required this.interruptible,
  });

  final PlaybackCommandCall transaction;
  final PlaybackCommandCall interrupt;
  final bool interruptible;

  Future<void>? _interruptFuture;
  bool started = false;
  bool completed = false;
  bool cancelledBeforeStart = false;

  Future<void> startTransaction() {
    try {
      return transaction();
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> requestInterrupt() {
    final previous = _interruptFuture;
    if (previous != null) {
      return previous;
    }

    try {
      final future = interrupt();
      _interruptFuture = future;
      _observeInterruptError(future);
      return future;
    } catch (error, stackTrace) {
      final future = Future<void>.error(error, stackTrace);
      _interruptFuture = future;
      _observeInterruptError(future);
      return future;
    }
  }

  void _observeInterruptError(Future<void> future) {
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  void cancelBeforeStart() {
    if (!started && !completed) {
      cancelledBeforeStart = true;
    }
  }

  Future<void> awaitCompletion(Future<void> completion) async {
    // Read the interrupt future after the transaction completes as well as
    // before it starts. A newer request can register its handshake while the
    // transaction is pending; taking a snapshot only at entry would release
    // the lane as soon as the transaction completes and race the handshake.
    Object? transactionError;
    StackTrace? transactionStackTrace;
    try {
      await completion;
    } catch (error, stackTrace) {
      transactionError = error;
      transactionStackTrace = stackTrace;
    }

    final interruptFuture = _interruptFuture;
    if (interruptFuture != null) {
      // Await both sides before releasing the graph lane. This remains true
      // when the transaction completed before the interrupt handshake did.
      try {
        await interruptFuture;
      } catch (error, stackTrace) {
        if (transactionError == null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
    }

    final error = transactionError;
    if (error != null) {
      Error.throwWithStackTrace(error, transactionStackTrace!);
    }
  }
}

final class _RetryFlight {
  const _RetryFlight({required this.targetKey, required this.future});

  final Object targetKey;
  final Future<void> future;
}

final class _PlayPauseBatch {
  _PlayPauseBatch({required this.desired, required this.platformCall});

  final bool desired;
  final PlaybackCommandCall platformCall;
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void completeSuccess() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}
