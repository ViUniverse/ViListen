// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  test(
    'Play UI and OS callbacks have parity from independent baselines',
    () async {
      final ui = await _runScenario(
        operation: (fixture) async {
          final command = fixture.gateway.play();
          await pumpEventQueue();
          fixture.engine.emitPlayerState(
            just_audio.PlayerState(true, just_audio.ProcessingState.ready),
          );
          expect(fixture.publications.snapshots, isEmpty);
          await command;
        },
      );
      final remote = await _runScenario(
        operation: (fixture) async {
          final command = fixture.handler.play();
          await pumpEventQueue();
          fixture.engine.emitPlayerState(
            just_audio.PlayerState(true, just_audio.ProcessingState.ready),
          );
          await command;
        },
      );

      _expectParity(ui, remote, command: 'play');
    },
  );

  test(
    'Pause UI and OS callbacks have parity from independent baselines',
    () async {
      final ui = await _runScenario(
        prepare: _preparePlaying,
        operation: (fixture) async {
          final command = fixture.gateway.pause();
          await pumpEventQueue();
          fixture.engine.emitPlayerState(
            just_audio.PlayerState(false, just_audio.ProcessingState.ready),
          );
          expect(fixture.publications.snapshots, isEmpty);
          await command;
        },
      );
      final remote = await _runScenario(
        prepare: _preparePlaying,
        operation: (fixture) async {
          final command = fixture.handler.pause();
          await pumpEventQueue();
          fixture.engine.emitPlayerState(
            just_audio.PlayerState(false, just_audio.ProcessingState.ready),
          );
          await command;
        },
      );

      _expectParity(ui, remote, command: 'pause');
    },
  );

  test(
    'Seek UI and OS callbacks have parity after position confirmation',
    () async {
      final ui = await _runSeekScenario(
        remote: false,
        target: const Duration(seconds: 18),
      );
      final remote = await _runSeekScenario(
        remote: true,
        target: const Duration(seconds: 18),
      );

      _expectParity(ui, remote, command: 'seek');
    },
  );

  test('Rewind and fast-forward callbacks share skipBy parity', () async {
    for (final direction in <_SkipDirection>[
      _SkipDirection.rewind,
      _SkipDirection.fastForward,
    ]) {
      final ui = await _runSkipScenario(direction, remote: false);
      final remote = await _runSkipScenario(direction, remote: true);

      _expectParity(ui, remote, command: 'skipBy');
      expect(ui.engineCalls, hasLength(1));
      expect(ui.engineCalls.single.name, 'seek');
      expect(ui.engineCalls.single.arguments['index'], isNull);
    }
  });

  test(
    'Next and Previous callbacks have parity from independent baselines',
    () async {
      for (final navigation in <_Navigation>[
        _Navigation.next,
        _Navigation.previous,
      ]) {
        final ui = await _runNavigationScenario(navigation, remote: false);
        final remote = await _runNavigationScenario(navigation, remote: true);

        _expectParity(
          ui,
          remote,
          command: navigation == _Navigation.next ? 'next' : 'previous',
        );
        expect(ui.engineCalls, hasLength(1));
        expect(ui.engineCalls.single.name, 'seek');
      }
    },
  );

  test('Speed callback parity waits for engine confirmation', () async {
    final ui = await _runScenario(
      operation: (fixture) async {
        final command = fixture.gateway.setSpeed(1.25);
        await pumpEventQueue();
        expect(fixture.publications.snapshots, isEmpty);
        fixture.engine.emitSpeed(1.25);
        await command;
      },
    );
    final remote = await _runScenario(
      operation: (fixture) async {
        final command = fixture.handler.setSpeed(1.25);
        await pumpEventQueue();
        expect(fixture.publications.snapshots, isEmpty);
        fixture.engine.emitSpeed(1.25);
        await command;
      },
    );

    _expectParity(ui, remote, command: 'setSpeed');
  });

  test('Repeat callback parity waits for loop-mode confirmation', () async {
    final ui = await _runScenario(
      operation: (fixture) async {
        final command = fixture.gateway.setRepeatMode(PlayerRepeatMode.one);
        await pumpEventQueue();
        expect(fixture.publications.snapshots, isEmpty);
        fixture.engine.emitLoopMode(just_audio.LoopMode.one);
        await command;
      },
    );
    final remote = await _runScenario(
      operation: (fixture) async {
        final command = fixture.handler.setRepeatMode(
          audio_service.AudioServiceRepeatMode.one,
        );
        await pumpEventQueue();
        expect(fixture.publications.snapshots, isEmpty);
        fixture.engine.emitLoopMode(just_audio.LoopMode.one);
        await command;
      },
    );

    _expectParity(ui, remote, command: 'setRepeatMode');
  });

  test(
    'Shuffle callback parity commits mode and sequence atomically',
    () async {
      final ui = await _runScenario(
        items: _shuffleItems,
        operation: (fixture) async {
          final command = fixture.gateway.setShuffleEnabled(true);
          await pumpEventQueue();
          expect(fixture.publications.snapshots, isEmpty);
          fixture.engine.emitShuffleModeEnabled(true);
          fixture.engine.emitEffectiveSequence(const <int>[1, 0]);
          await command;
        },
      );
      final remote = await _runScenario(
        items: _shuffleItems,
        operation: (fixture) async {
          final command = fixture.handler.setShuffleMode(
            audio_service.AudioServiceShuffleMode.all,
          );
          await pumpEventQueue();
          expect(fixture.publications.snapshots, isEmpty);
          fixture.engine.emitShuffleModeEnabled(true);
          fixture.engine.emitEffectiveSequence(const <int>[1, 0]);
          await command;
        },
      );

      _expectParity(ui, remote, command: 'setShuffleEnabled');
      expect(ui.publications.snapshots, hasLength(1));
      expect(ui.publications.queues, hasLength(1));
      expect(ui.publications.playbackStates, hasLength(1));
      expect(ui.publications.snapshots.single.shuffleEnabled, isTrue);
      expect(ui.publications.snapshots.single.currentItem?.id, 'shuffle-a');
      expect(ui.publications.snapshots.single.currentIndex, 1);
    },
  );

  test(
    'Cubit created after a remote command replays the latest snapshot',
    () async {
      final fixture = _HandlerFixture();
      await fixture.listenToPublications();
      PlayerCubit? cubit;
      try {
        await _loadReady(fixture);
        fixture.resetPublications();

        final remote = fixture.handler.play();
        await pumpEventQueue();
        expect(fixture.engine.callCountFor('play'), 1);

        fixture.engine.emitPlayerState(
          just_audio.PlayerState(true, just_audio.ProcessingState.ready),
        );
        await remote;
        await pumpEventQueue();

        final engineCallCount = fixture.engine.calls.length;
        final observerCallCount = fixture.observedCommands.length;
        cubit = PlayerCubit(fixture.gateway);

        expect(cubit.state.playback, PlaybackSnapshot.idle);
        expect(fixture.engine.calls, hasLength(engineCallCount));
        expect(fixture.observedCommands, hasLength(observerCallCount));

        await pumpEventQueue();

        expect(cubit.state.playing, isTrue);
        expect(cubit.state.currentItem?.id, 'remote-parity-track');
        expect(
          cubit.state.playback.processingState,
          PlaybackProcessingState.ready,
        );
        expect(fixture.engine.calls, hasLength(engineCallCount));
        expect(fixture.observedCommands, hasLength(observerCallCount));
      } finally {
        if (cubit != null && !cubit.isClosed) {
          await cubit.close();
        }
        await fixture.dispose();
      }
    },
  );
}

final _shuffleItems = <PlayerItem>[
  PlayerItem(
    id: 'shuffle-a',
    audioUri: Uri.parse('https://cdn.example.test/audio/shuffle-a.mp3'),
    title: 'Shuffle A',
    artist: 'Test artist',
  ),
  PlayerItem(
    id: 'shuffle-b',
    audioUri: Uri.parse('https://cdn.example.test/audio/shuffle-b.mp3'),
    title: 'Shuffle B',
    artist: 'Test artist',
  ),
];

Future<void> _preparePlaying(_HandlerFixture fixture) async {
  fixture.engine.emitPlayerState(
    just_audio.PlayerState(true, just_audio.ProcessingState.ready),
  );
  await pumpEventQueue();
}

Future<_ScenarioResult> _runSeekScenario({
  required bool remote,
  required Duration target,
}) => _runScenario(
  operation: (fixture) async {
    final command = remote
        ? fixture.handler.seek(target)
        : fixture.gateway.seek(target);
    await pumpEventQueue();
    expect(fixture.publications.snapshots, isEmpty);
    fixture.engine.emitPosition(target);
    fixture.clock.advance(const Duration(seconds: 1));
    await command;
  },
);

Future<_ScenarioResult> _runSkipScenario(
  _SkipDirection direction, {
  required bool remote,
}) => _runScenario(
  operation: (fixture) async {
    final command = switch ((remote, direction)) {
      (false, _SkipDirection.rewind) => fixture.gateway.skipBy(
        const Duration(seconds: -10),
      ),
      (false, _SkipDirection.fastForward) => fixture.gateway.skipBy(
        const Duration(seconds: 10),
      ),
      (true, _SkipDirection.rewind) => fixture.handler.rewind(),
      (true, _SkipDirection.fastForward) => fixture.handler.fastForward(),
    };
    await pumpEventQueue();
    final target = direction == _SkipDirection.rewind
        ? const Duration(seconds: 20)
        : const Duration(seconds: 40);
    expect(fixture.publications.snapshots, isEmpty);
    fixture.engine.emitPosition(target);
    fixture.clock.advance(const Duration(seconds: 1));
    await command;
  },
  position: const Duration(seconds: 30),
);

Future<_ScenarioResult> _runNavigationScenario(
  _Navigation navigation, {
  required bool remote,
}) => _runScenario(
  initialIndex: 1,
  items: _navigationItems,
  operation: (fixture) async {
    final command = switch ((remote, navigation)) {
      (false, _Navigation.next) => fixture.gateway.next(),
      (false, _Navigation.previous) => fixture.gateway.previous(),
      (true, _Navigation.next) => fixture.handler.skipToNext(),
      (true, _Navigation.previous) => fixture.handler.skipToPrevious(),
    };
    await pumpEventQueue();
    expect(fixture.publications.snapshots, isEmpty);
    fixture.engine.emitCurrentIndex(navigation == _Navigation.next ? 2 : 0);
    await command;
  },
);

Future<_ScenarioResult> _runScenario({
  List<PlayerItem>? items,
  int initialIndex = 0,
  Duration position = Duration.zero,
  Future<void> Function(_HandlerFixture fixture)? prepare,
  required Future<void> Function(_HandlerFixture fixture) operation,
}) async {
  final fixture = _HandlerFixture();
  await fixture.listenToPublications();
  try {
    await _loadReady(
      fixture,
      items: items ?? _defaultItems,
      initialIndex: initialIndex,
      position: position,
    );
    if (prepare != null) {
      await prepare(fixture);
    }
    fixture.resetPublications();
    final operationStart = fixture.engine.calls.length;

    await operation(fixture);
    await pumpEventQueue();

    return fixture.result(operationStart);
  } finally {
    await fixture.dispose();
  }
}

Future<void> _loadReady(
  _HandlerFixture fixture, {
  List<PlayerItem>? items,
  int initialIndex = 0,
  Duration position = Duration.zero,
}) async {
  final load = fixture.handler.handleLoadQueue(
    items ?? _defaultItems,
    initialIndex,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  fixture.engine.emitDuration(const Duration(seconds: 60));
  fixture.engine.emitPosition(position);
  fixture.engine.loadRequests.last.complete();
  await load;
  await pumpEventQueue();
}

void _expectParity(
  _ScenarioResult ui,
  _ScenarioResult remote, {
  required String command,
}) {
  expect(ui.engineCalls, hasLength(remote.engineCalls.length));
  for (var index = 0; index < ui.engineCalls.length; index++) {
    expect(ui.engineCalls[index].name, remote.engineCalls[index].name);
    _expectArgumentsEqual(
      ui.engineCalls[index].arguments,
      remote.engineCalls[index].arguments,
    );
  }
  expect(ui.publications, remote.publications);
  expect(ui.observedCommands.single.command, command);
  expect(remote.observedCommands.single.command, command);
  expect(ui.observedCommands.single.source, CommandSource.ui);
  expect(remote.observedCommands.single.source, CommandSource.systemRemote);
}

void _expectArgumentsEqual(
  Map<String, Object?> first,
  Map<String, Object?> second,
) {
  expect(first.keys, second.keys);
  for (final key in first.keys) {
    expect(first[key], second[key]);
  }
}

final class _HandlerFixture {
  _HandlerFixture()
    : engine = FakePlaybackEngine(),
      clock = FakePlayerClock(),
      observedCommands = <({String command, CommandSource source})>[] {
    handler = AppAudioHandler(engine, clock, (command, source) {
      observedCommands.add((command: command, source: source));
    });
    gateway = UiPlaybackGatewayAdapter(handler);
  }

  final FakePlaybackEngine engine;
  final FakePlayerClock clock;
  final List<({String command, CommandSource source})> observedCommands;
  final _PublicationCapture publications = _PublicationCapture();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  late final AppAudioHandler handler;
  late final UiPlaybackGatewayAdapter gateway;

  Future<void> listenToPublications() async {
    _subscriptions
      ..add(handler.snapshots.listen(publications.snapshots.add))
      ..add(handler.mediaItem.listen(publications.mediaItems.add))
      ..add(
        handler.queue.listen(
          (items) => publications.queues.add(
            items.map((item) => item.id).toList(growable: false),
          ),
        ),
      )
      ..add(
        handler.playbackState.listen(
          (state) => publications.playbackStates.add(
            _PlaybackStateSummary.from(state),
          ),
        ),
      );
    await pumpEventQueue();
  }

  void resetPublications() {
    publications.clear();
    observedCommands.clear();
  }

  _ScenarioResult result(int operationStart) => _ScenarioResult(
    engineCalls: engine.calls
        .skip(operationStart)
        .map((call) => _EngineCall(call.name, call.arguments))
        .toList(growable: false),
    observedCommands:
        List<({String command, CommandSource source})>.unmodifiable(
          observedCommands,
        ),
    publications: publications.copy(),
  );

  Future<void> dispose() async {
    await Future.wait<void>(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await handler.dispose();
  }
}

final class _ScenarioResult {
  const _ScenarioResult({
    required this.engineCalls,
    required this.observedCommands,
    required this.publications,
  });

  final List<_EngineCall> engineCalls;
  final List<({String command, CommandSource source})> observedCommands;
  final _PublicationCapture publications;
}

final class _EngineCall {
  _EngineCall(this.name, Map<String, Object?> arguments)
    : arguments = Map<String, Object?>.unmodifiable(arguments);

  final String name;
  final Map<String, Object?> arguments;
}

final class _PublicationCapture {
  final List<PlaybackSnapshot> snapshots = <PlaybackSnapshot>[];
  final List<audio_service.MediaItem?> mediaItems =
      <audio_service.MediaItem?>[];
  final List<List<String>> queues = <List<String>>[];
  final List<_PlaybackStateSummary> playbackStates = <_PlaybackStateSummary>[];

  _PublicationCapture copy() {
    final copy = _PublicationCapture();
    copy.snapshots.addAll(snapshots);
    copy.mediaItems.addAll(mediaItems);
    copy.queues.addAll(queues.map((queue) => List<String>.unmodifiable(queue)));
    copy.playbackStates.addAll(playbackStates);
    return copy;
  }

  void clear() {
    snapshots.clear();
    mediaItems.clear();
    queues.clear();
    playbackStates.clear();
  }

  @override
  bool operator ==(Object other) =>
      other is _PublicationCapture &&
      other.snapshots.length == snapshots.length &&
      _listEquals(other.snapshots, snapshots) &&
      _listEquals(
        other.mediaItems.map((item) => item?.id).toList(),
        mediaItems.map((item) => item?.id).toList(),
      ) &&
      _nestedListEquals(other.queues, queues) &&
      _listEquals(other.playbackStates, playbackStates);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(snapshots),
    Object.hashAll(mediaItems),
    Object.hashAll(queues),
    Object.hashAll(playbackStates),
  );
}

final class _PlaybackStateSummary {
  const _PlaybackStateSummary({
    required this.processingState,
    required this.playing,
    required this.position,
    required this.bufferedPosition,
    required this.speed,
    required this.repeatMode,
    required this.shuffleMode,
    required this.queueIndex,
    required this.errorCode,
    required this.errorMessage,
  });

  factory _PlaybackStateSummary.from(audio_service.PlaybackState state) =>
      _PlaybackStateSummary(
        processingState: state.processingState,
        playing: state.playing,
        position: state.updatePosition,
        bufferedPosition: state.bufferedPosition,
        speed: state.speed,
        repeatMode: state.repeatMode,
        shuffleMode: state.shuffleMode,
        queueIndex: state.queueIndex,
        errorCode: state.errorCode,
        errorMessage: state.errorMessage,
      );

  final audio_service.AudioProcessingState processingState;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final double speed;
  final audio_service.AudioServiceRepeatMode repeatMode;
  final audio_service.AudioServiceShuffleMode shuffleMode;
  final int? queueIndex;
  final int? errorCode;
  final String? errorMessage;

  @override
  bool operator ==(Object other) =>
      other is _PlaybackStateSummary &&
      other.processingState == processingState &&
      other.playing == playing &&
      other.position == position &&
      other.bufferedPosition == bufferedPosition &&
      other.speed == speed &&
      other.repeatMode == repeatMode &&
      other.shuffleMode == shuffleMode &&
      other.queueIndex == queueIndex &&
      other.errorCode == errorCode &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
    processingState,
    playing,
    position,
    bufferedPosition,
    speed,
    repeatMode,
    shuffleMode,
    queueIndex,
    errorCode,
    errorMessage,
  );
}

bool _listEquals<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

bool _nestedListEquals<T>(List<List<T>> first, List<List<T>> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (!_listEquals(first[index], second[index])) {
      return false;
    }
  }
  return true;
}

final _defaultItems = <PlayerItem>[testPlayerItem(id: 'remote-parity-track')];

final _navigationItems = <PlayerItem>[
  PlayerItem(
    id: 'navigation-a',
    audioUri: Uri.parse('https://cdn.example.test/audio/navigation-a.mp3'),
    title: 'Navigation A',
    artist: 'Test artist',
  ),
  PlayerItem(
    id: 'navigation-b',
    audioUri: Uri.parse('https://cdn.example.test/audio/navigation-b.mp3'),
    title: 'Navigation B',
    artist: 'Test artist',
  ),
  PlayerItem(
    id: 'navigation-c',
    audioUri: Uri.parse('https://cdn.example.test/audio/navigation-c.mp3'),
    title: 'Navigation C',
    artist: 'Test artist',
  ),
];

enum _SkipDirection { rewind, fastForward }

enum _Navigation { next, previous }
