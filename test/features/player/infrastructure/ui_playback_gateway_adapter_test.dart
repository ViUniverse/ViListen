import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/playback_gateway.dart';
import 'package:ten_project_cua_ban/features/player/application/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/command_source.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/ui_playback_command_target.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/ui_playback_gateway_adapter.dart';

void main() {
  test('forwards the target snapshot stream unchanged', () async {
    final target = _FakeUiPlaybackCommandTarget();
    final adapter = UiPlaybackGatewayAdapter(target);
    final snapshots = <PlaybackSnapshot>[];
    final subscription = adapter.snapshots.listen(snapshots.add);

    target.emit(PlaybackSnapshot.idle);
    await pumpEventQueue();

    expect(snapshots, [PlaybackSnapshot.idle]);
    await subscription.cancel();
    await target.dispose();
  });

  test(
    'forwards every UI command with arguments and source in order',
    () async {
      final target = _FakeUiPlaybackCommandTarget();
      final adapter = UiPlaybackGatewayAdapter(target);
      final item = PlayerItem(
        id: 'track-1',
        audioUri: Uri.parse('https://example.com/track-1.mp3'),
        title: 'Track 1',
        artist: 'Artist',
      );

      await adapter.loadQueue([item], initialIndex: 1, autoplay: false);
      await adapter.play();
      await adapter.pause();
      await adapter.stop();
      await adapter.seek(const Duration(seconds: 4));
      await adapter.skipBy(const Duration(seconds: -10));
      await adapter.next();
      await adapter.previous();
      await adapter.setSpeed(1.25);
      await adapter.setRepeatMode(PlayerRepeatMode.all);
      await adapter.setShuffleEnabled(true);
      await adapter.retry();

      expect(target.calls, [
        _TargetCall('loadQueue', <Object?>[
          [item],
          1,
          false,
        ], CommandSource.ui),
        _TargetCall('play', const <Object?>[], CommandSource.ui),
        _TargetCall('pause', const <Object?>[], CommandSource.ui),
        _TargetCall('stop', const <Object?>[], CommandSource.ui),
        _TargetCall('seek', const <Object?>[
          Duration(seconds: 4),
        ], CommandSource.ui),
        _TargetCall('skipBy', const <Object?>[
          Duration(seconds: -10),
        ], CommandSource.ui),
        _TargetCall('next', const <Object?>[], CommandSource.ui),
        _TargetCall('previous', const <Object?>[], CommandSource.ui),
        _TargetCall('setSpeed', const <Object?>[1.25], CommandSource.ui),
        _TargetCall('setRepeatMode', const <Object?>[
          PlayerRepeatMode.all,
        ], CommandSource.ui),
        _TargetCall('setShuffleEnabled', const <Object?>[
          true,
        ], CommandSource.ui),
        _TargetCall('retry', const <Object?>[], CommandSource.ui),
      ]);

      await target.dispose();
    },
  );

  test('the same target operation can be called by an OS source', () async {
    final target = _FakeUiPlaybackCommandTarget();
    final adapter = UiPlaybackGatewayAdapter(target);

    await adapter.play();
    await target.play(CommandSource.systemRemote);

    expect(target.calls, [
      _TargetCall('play', const <Object?>[], CommandSource.ui),
      _TargetCall('play', const <Object?>[], CommandSource.systemRemote),
    ]);

    await target.dispose();
  });

  test(
    'PlayerCubit is composed through PlaybackGateway, not the target',
    () async {
      final target = _FakeUiPlaybackCommandTarget();
      final PlaybackGateway gateway = UiPlaybackGatewayAdapter(target);
      final cubit = PlayerCubit(gateway);

      expect(cubit, isA<PlayerCubit>());

      await cubit.close();
      await target.dispose();
    },
  );
}

final class _TargetCall {
  const _TargetCall(this.name, this.arguments, this.source);

  final String name;
  final List<Object?> arguments;
  final CommandSource source;

  @override
  bool operator ==(Object other) =>
      other is _TargetCall &&
      other.name == name &&
      _listEquals(other.arguments, arguments) &&
      other.source == source;

  @override
  int get hashCode => Object.hash(name, Object.hashAll(arguments), source);
}

bool _listEquals(List<Object?> first, List<Object?> second) {
  if (first.length != second.length) {
    return false;
  }

  for (var index = 0; index < first.length; index++) {
    if (!_valueEquals(first[index], second[index])) {
      return false;
    }
  }
  return true;
}

bool _valueEquals(Object? first, Object? second) {
  if (first is List<Object?> && second is List<Object?>) {
    return _listEquals(first, second);
  }
  return first == second;
}

final class _FakeUiPlaybackCommandTarget implements UiPlaybackCommandTarget {
  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();
  final List<_TargetCall> calls = <_TargetCall>[];

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> loadQueue(
    List<PlayerItem> items,
    int initialIndex,
    bool autoplay,
    CommandSource source,
  ) async {
    _record('loadQueue', <Object?>[items, initialIndex, autoplay], source);
  }

  @override
  Future<void> play(CommandSource source) async {
    _record('play', const <Object?>[], source);
  }

  @override
  Future<void> pause(CommandSource source) async {
    _record('pause', const <Object?>[], source);
  }

  @override
  Future<void> stop(CommandSource source) async {
    _record('stop', const <Object?>[], source);
  }

  @override
  Future<void> seek(Duration position, CommandSource source) async {
    _record('seek', <Object?>[position], source);
  }

  @override
  Future<void> skipBy(Duration offset, CommandSource source) async {
    _record('skipBy', <Object?>[offset], source);
  }

  @override
  Future<void> next(CommandSource source) async {
    _record('next', const <Object?>[], source);
  }

  @override
  Future<void> previous(CommandSource source) async {
    _record('previous', const <Object?>[], source);
  }

  @override
  Future<void> setSpeed(double speed, CommandSource source) async {
    _record('setSpeed', <Object?>[speed], source);
  }

  @override
  Future<void> setRepeatMode(
    PlayerRepeatMode mode,
    CommandSource source,
  ) async {
    _record('setRepeatMode', <Object?>[mode], source);
  }

  @override
  Future<void> setShuffleEnabled(bool enabled, CommandSource source) async {
    _record('setShuffleEnabled', <Object?>[enabled], source);
  }

  @override
  Future<void> retry(CommandSource source) async {
    _record('retry', const <Object?>[], source);
  }

  void emit(PlaybackSnapshot snapshot) => _controller.add(snapshot);

  Future<void> dispose() => _controller.close();

  void _record(String name, List<Object?> arguments, CommandSource source) {
    calls.add(_TargetCall(name, arguments, source));
  }
}
