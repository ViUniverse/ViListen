// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:ten_project_cua_ban/features/player/application/playback_gateway.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

typedef FakeCommandBehavior = FutureOr<void> Function(RecordedCommand command);

final class RecordedCommand {
  RecordedCommand({
    required this.name,
    required Map<String, Object?> arguments,
    required this.order,
    required this.callCount,
  }) : arguments = Map<String, Object?>.unmodifiable(arguments);

  final String name;
  final Map<String, Object?> arguments;
  final int order;
  final int callCount;
}

final class FakePlaybackGateway implements PlaybackGateway {
  FakePlaybackGateway({
    PlaybackSnapshot initialSnapshot = PlaybackSnapshot.idle,
    Map<String, FakeCommandBehavior> commandBehaviors =
        const <String, FakeCommandBehavior>{},
  }) : _latestSnapshot = initialSnapshot,
       _commandBehaviors = Map<String, FakeCommandBehavior>.from(
         commandBehaviors,
       );

  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<RecordedCommand> _commands = <RecordedCommand>[];
  final Map<String, int> _callCounts = <String, int>{};
  final Map<String, FakeCommandBehavior> _commandBehaviors;

  PlaybackSnapshot _latestSnapshot;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Stream<PlaybackSnapshot> get snapshots =>
      Stream<PlaybackSnapshot>.multi((subscriber) {
        if (_disposed) {
          subscriber.close();
          return;
        }

        final replay = _latestSnapshot;
        final sourceSubscription = _controller.stream.listen(
          subscriber.add,
          onError: (Object error, StackTrace stackTrace) {
            subscriber.addError(error, stackTrace);
          },
          onDone: subscriber.close,
        );
        subscriber.onCancel = () {
          snapshotSubscriptionCancelCount += 1;
          return sourceSubscription.cancel();
        };

        scheduleMicrotask(() {
          if (!_disposed && !subscriber.isClosed) {
            subscriber.addSync(replay);
          }
        });
      }, isBroadcast: true);

  List<RecordedCommand> get commands =>
      List<RecordedCommand>.unmodifiable(_commands);

  int snapshotSubscriptionCancelCount = 0;

  int callCountFor(String commandName) => _callCounts[commandName] ?? 0;

  void emit(PlaybackSnapshot snapshot) {
    _latestSnapshot = snapshot;
    _controller.add(snapshot);
  }

  @override
  Future<void> loadQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    bool autoplay = true,
  }) => _execute(
    'loadQueue',
    arguments: <String, Object?>{
      'items': List<PlayerItem>.unmodifiable(items),
      'initialIndex': initialIndex,
      'autoplay': autoplay,
    },
  );

  @override
  Future<void> play() => _execute('play');

  @override
  Future<void> pause() => _execute('pause');

  @override
  Future<void> stop() => _execute('stop');

  @override
  Future<void> seek(Duration position) =>
      _execute('seek', arguments: <String, Object?>{'position': position});

  @override
  Future<void> skipBy(Duration offset) =>
      _execute('skipBy', arguments: <String, Object?>{'offset': offset});

  @override
  Future<void> next() => _execute('next');

  @override
  Future<void> previous() => _execute('previous');

  @override
  Future<void> setSpeed(double speed) =>
      _execute('setSpeed', arguments: <String, Object?>{'speed': speed});

  @override
  Future<void> setRepeatMode(PlayerRepeatMode mode) =>
      _execute('setRepeatMode', arguments: <String, Object?>{'mode': mode});

  @override
  Future<void> setShuffleEnabled(bool enabled) => _execute(
    'setShuffleEnabled',
    arguments: <String, Object?>{'enabled': enabled},
  );

  @override
  Future<void> retry() => _execute('retry');

  Future<void> dispose() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) {
      return disposeFuture;
    }

    _disposed = true;
    return _disposeFuture = _controller.close();
  }

  Future<void> _execute(
    String name, {
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    final callCount = (_callCounts[name] ?? 0) + 1;
    final command = RecordedCommand(
      name: name,
      arguments: arguments,
      order: _commands.length + 1,
      callCount: callCount,
    );
    _commands.add(command);
    _callCounts[name] = callCount;

    final behavior = _commandBehaviors[name];
    if (behavior == null) {
      return Future<void>.value();
    }
    return Future<void>.sync(() => behavior(command));
  }
}
