// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/engine/playback_engine.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late _RepeatTestEngine engine;
  late AppAudioHandler handler;

  setUp(() {
    engine = _RepeatTestEngine(FakePlaybackEngine());
    handler = AppAudioHandler(engine, FakePlayerClock());
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('maps every domain repeat mode to the engine loop mode', () async {
    await _loadReady(handler, engine, 'repeat-mapping-track');

    const modes = <PlayerRepeatMode>[
      PlayerRepeatMode.off,
      PlayerRepeatMode.one,
      PlayerRepeatMode.all,
    ];
    const loopModes = <just_audio.LoopMode>[
      just_audio.LoopMode.off,
      just_audio.LoopMode.one,
      just_audio.LoopMode.all,
    ];

    for (var index = 0; index < modes.length; index++) {
      await handler.handleSetRepeatMode(modes[index], CommandSource.ui);
      expect(engine.loopCalls.last, loopModes[index]);
      engine.emitLoopMode(loopModes[index]);
      await pumpEventQueue();
      expect(
        handler.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.values[index == 0 ? 0 : index],
      );
    }
  });

  test(
    'publishes snapshot and OS repeat only after loop-mode confirmation',
    () async {
      final snapshots = <PlaybackSnapshot>[];
      final playbackStates = <audio_service.PlaybackState>[];
      final queueEvents = <List<audio_service.MediaItem>>[];
      final mediaEvents = <audio_service.MediaItem?>[];
      final snapshotSubscription = handler.snapshots.listen(snapshots.add);
      final playbackSubscription = handler.playbackState.listen(
        playbackStates.add,
      );
      final queueSubscription = handler.queue.listen(queueEvents.add);
      final mediaSubscription = handler.mediaItem.listen(mediaEvents.add);
      addTearDown(snapshotSubscription.cancel);
      addTearDown(playbackSubscription.cancel);
      addTearDown(queueSubscription.cancel);
      addTearDown(mediaSubscription.cancel);

      await _loadReady(handler, engine, 'repeat-confirmation-track');
      await pumpEventQueue();
      snapshots.clear();
      playbackStates.clear();
      queueEvents.clear();
      mediaEvents.clear();

      final platformCall = Completer<void>();
      engine.loopAction = (_) => platformCall.future;
      final operation = handler.handleSetRepeatMode(
        PlayerRepeatMode.one,
        CommandSource.ui,
      );
      await pumpEventQueue();

      expect(
        handler.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.none,
      );
      expect(snapshots, isEmpty);
      expect(playbackStates, isEmpty);

      platformCall.complete();
      await operation;
      await pumpEventQueue();
      expect(snapshots, isEmpty);
      expect(playbackStates, isEmpty);

      engine.emitLoopMode(just_audio.LoopMode.one);
      await pumpEventQueue();

      expect(snapshots, hasLength(1));
      expect(snapshots.single.repeatMode, PlayerRepeatMode.one);
      expect(playbackStates, hasLength(1));
      expect(
        playbackStates.single.repeatMode,
        audio_service.AudioServiceRepeatMode.one,
      );
      expect(queueEvents, isEmpty);
      expect(mediaEvents, isEmpty);
    },
  );

  test('coalesces identical repeat requests into one engine call', () async {
    await _loadReady(handler, engine, 'repeat-coalesce-track');
    final platformCall = Completer<void>();
    engine.loopAction = (_) => platformCall.future;

    final first = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );
    final second = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );

    expect(identical(first, second), isTrue);
    expect(engine.loopCalls, [just_audio.LoopMode.one]);

    platformCall.complete();
    await first;
    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.one,
    );
  });

  test('keeps the latest mode in a ready A-B-A burst', () async {
    await _loadReady(handler, engine, 'repeat-ready-a-b-a-track');
    final firstPlatformCall = Completer<void>();
    var callNumber = 0;
    engine.loopAction = (_) {
      callNumber += 1;
      return callNumber == 1 ? firstPlatformCall.future : Future<void>.value();
    };

    final firstA = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );
    final b = handler.handleSetRepeatMode(
      PlayerRepeatMode.all,
      CommandSource.ui,
    );
    final lastA = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );

    expect(engine.loopCalls, [just_audio.LoopMode.one]);

    firstPlatformCall.complete();
    await Future.wait<void>([firstA, b, lastA]);
    await pumpEventQueue();

    expect(engine.loopCalls, [
      just_audio.LoopMode.one,
      just_audio.LoopMode.one,
    ]);
    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.one,
    );
    expect(engine.loopCalls, isNot(contains(just_audio.LoopMode.all)));
  });

  test('ignores a stale A confirmation after B becomes desired', () async {
    await _loadReady(handler, engine, 'repeat-stale-confirmation-track');
    final firstPlatformCall = Completer<void>();
    final secondPlatformCall = Completer<void>();
    engine.loopAction = (mode) => mode == just_audio.LoopMode.one
        ? firstPlatformCall.future
        : secondPlatformCall.future;

    final first = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );
    final second = handler.handleSetRepeatMode(
      PlayerRepeatMode.all,
      CommandSource.ui,
    );

    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.none,
    );

    firstPlatformCall.complete();
    await first;
    await pumpEventQueue();
    expect(engine.loopCalls, [
      just_audio.LoopMode.one,
      just_audio.LoopMode.all,
    ]);

    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.none,
    );

    secondPlatformCall.complete();
    await second;
    engine.emitLoopMode(just_audio.LoopMode.all);
    await pumpEventQueue();
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.all,
    );
  });

  test('keeps the latest mode in a pending-load A-B-A burst', () async {
    final load = handler.handleLoadQueue(
      [testPlayerItem(id: 'repeat-pending-a-b-a-track')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    final firstPlatformCall = Completer<void>();
    var callNumber = 0;
    engine.loopAction = (_) {
      callNumber += 1;
      return callNumber == 1 ? firstPlatformCall.future : Future<void>.value();
    };
    final firstA = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );
    final b = handler.handleSetRepeatMode(
      PlayerRepeatMode.all,
      CommandSource.ui,
    );
    final lastA = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );

    firstPlatformCall.complete();
    await Future.wait<void>([firstA, b, lastA]);
    expect(engine.loopCalls, [
      just_audio.LoopMode.one,
      just_audio.LoopMode.one,
    ]);

    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    engine.loadRequests.single.complete();
    await load;
    await pumpEventQueue();

    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.one,
    );
  });

  test('reapplies the same desired mode for a new load generation', () async {
    await _loadReady(handler, engine, 'repeat-generation-a');
    await handler.handleSetRepeatMode(PlayerRepeatMode.one, CommandSource.ui);
    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();

    final secondPlatformCall = Completer<void>();
    engine.loopAction = (_) => secondPlatformCall.future;
    final load = handler.handleLoadQueue(
      [testPlayerItem(id: 'repeat-generation-b')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    engine.loadRequests.last.complete();
    await pumpEventQueue();

    expect(engine.loopCalls, [
      just_audio.LoopMode.one,
      just_audio.LoopMode.one,
    ]);
    expect(handler.mediaItem.value?.id, 'repeat-generation-a');

    engine.emitLoopMode(just_audio.LoopMode.one);
    await pumpEventQueue();
    expect(handler.mediaItem.value?.id, 'repeat-generation-a');
    secondPlatformCall.complete();
    await load;
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, 'repeat-generation-b');
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.one,
    );
  });

  test('a newer load replaces a load waiting on repeat confirmation', () async {
    await _loadReady(handler, engine, 'repeat-replacement-a');
    final loadC = handler.handleLoadQueue(
      [testPlayerItem(id: 'repeat-replacement-c')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();

    final cPlatformCall = Completer<void>();
    final dPlatformCall = Completer<void>();
    var callNumber = 0;
    engine.loopAction = (_) {
      callNumber += 1;
      return callNumber == 1 ? cPlatformCall.future : dPlatformCall.future;
    };
    final cRepeat = handler.handleSetRepeatMode(
      PlayerRepeatMode.one,
      CommandSource.ui,
    );
    engine.loadRequests[1].complete();
    await pumpEventQueue();

    final loadD = handler.handleLoadQueue(
      [testPlayerItem(id: 'repeat-replacement-d')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    expect(engine.loadRequests, hasLength(3));

    engine.loadRequests[2].complete();
    await pumpEventQueue();
    expect(engine.loopCalls, [
      just_audio.LoopMode.one,
      just_audio.LoopMode.one,
    ]);

    engine.emitLoopMode(just_audio.LoopMode.one);
    dPlatformCall.complete();
    await Future.wait<void>([loadC, loadD, cRepeat]);
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, 'repeat-replacement-d');
    expect(
      handler.playbackState.value.repeatMode,
      audio_service.AudioServiceRepeatMode.one,
    );

    // The interrupted platform call may settle after D has committed.
    cPlatformCall.complete();
  });

  test('rejects idle and loading commands without an engine call', () async {
    await expectLater(
      handler.handleSetRepeatMode(PlayerRepeatMode.one, CommandSource.ui),
      _noCurrentItemFailure,
    );
    expect(engine.loopCalls, isEmpty);

    engine.emitPlayerState(
      just_audio.PlayerState(false, just_audio.ProcessingState.loading),
    );
    await pumpEventQueue();
    await expectLater(
      handler.handleSetRepeatMode(PlayerRepeatMode.one, CommandSource.ui),
      _commandUnavailableFailure,
    );
    expect(engine.loopCalls, isEmpty);

    final load = handler.handleLoadQueue(
      [testPlayerItem(id: 'repeat-loading-track')],
      0,
      false,
      CommandSource.ui,
    );
    await pumpEventQueue();
    // The pending-load branch is intentionally valid and is tested above.
    expect(handler.playbackState.value.processingState.name, 'loading');
    expect(engine.loopCalls, isEmpty);

    engine.loadRequests.single.complete();
    await load;
  });

  test(
    'engine failure releases the repeat flight for the next command',
    () async {
      await _loadReady(handler, engine, 'repeat-failure-track');
      engine.loopAction = (_) => Future<void>.error(StateError('loop failed'));

      await expectLater(
        handler.handleSetRepeatMode(PlayerRepeatMode.one, CommandSource.ui),
        throwsA(isA<StateError>()),
      );
      expect(
        handler.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.none,
      );

      engine.loopAction = (_) => Future<void>.value();
      final next = handler.handleSetRepeatMode(
        PlayerRepeatMode.all,
        CommandSource.ui,
      );
      engine.emitLoopMode(just_audio.LoopMode.all);
      await next;
      await pumpEventQueue();
      expect(
        handler.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.all,
      );
    },
  );

  test(
    'repeat-off completion keeps the item for the completion owner',
    () async {
      final item = testPlayerItem(id: 'repeat-off-completion-track');
      await _loadReady(handler, engine, item.id);

      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.completed),
      );
      await pumpEventQueue();

      expect(
        handler.playbackState.value.processingState,
        audio_service.AudioProcessingState.completed,
      );
      expect(handler.mediaItem.value?.id, item.id);

      final repeat = handler.handleSetRepeatMode(
        PlayerRepeatMode.one,
        CommandSource.ui,
      );
      engine.emitLoopMode(just_audio.LoopMode.one);
      await repeat;
      await pumpEventQueue();
      expect(
        handler.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.one,
      );
    },
  );

  test(
    'repeat one and all leave completion navigation to the engine',
    () async {
      final cases =
          <({PlayerRepeatMode mode, int initialIndex, int completedIndex})>[
            (mode: PlayerRepeatMode.one, initialIndex: 0, completedIndex: 0),
            (mode: PlayerRepeatMode.all, initialIndex: 1, completedIndex: 0),
          ];

      for (final testCase in cases) {
        final localEngine = _RepeatTestEngine(FakePlaybackEngine());
        final localHandler = AppAudioHandler(localEngine, FakePlayerClock());
        addTearDown(localHandler.dispose);
        await _loadReady(
          localHandler,
          localEngine,
          'repeat-${testCase.mode.name}-completion-track',
          initialIndex: testCase.initialIndex,
          itemCount: 2,
        );
        await localHandler.handleSetRepeatMode(testCase.mode, CommandSource.ui);
        localEngine.emitLoopMode(_toLoopMode(testCase.mode));
        await pumpEventQueue();
        final callCount = localEngine.calls.length;

        localEngine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.completed),
        );
        localEngine.emitCurrentIndex(testCase.completedIndex);
        await pumpEventQueue();

        expect(
          localEngine.calls.skip(callCount).map((call) => call.name).toList(),
          everyElement(isNot(anyOf('seek', 'play', 'pause'))),
        );
      }
    },
  );
}

Matcher get _noCurrentItemFailure => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', 'noCurrentItem')
      .having((failure) => failure.command, 'command', 'setRepeatMode'),
);

Matcher get _commandUnavailableFailure => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', 'commandUnavailable')
      .having((failure) => failure.command, 'command', 'setRepeatMode'),
);

Future<void> _loadReady(
  AppAudioHandler handler,
  _RepeatTestEngine engine,
  String id, {
  int initialIndex = 0,
  int itemCount = 1,
}) async {
  final items = List.generate(
    itemCount,
    (index) => testPlayerItem(id: itemCount == 1 ? id : '$id-$index'),
  );
  final load = handler.handleLoadQueue(
    items,
    initialIndex,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.loadRequests.last.complete();
  await load;
  await pumpEventQueue();
}

just_audio.LoopMode _toLoopMode(PlayerRepeatMode mode) => switch (mode) {
  PlayerRepeatMode.off => just_audio.LoopMode.off,
  PlayerRepeatMode.one => just_audio.LoopMode.one,
  PlayerRepeatMode.all => just_audio.LoopMode.all,
};

final class _RepeatTestEngine implements PlaybackEngine {
  _RepeatTestEngine(this.delegate);

  final FakePlaybackEngine delegate;
  Future<void> Function(just_audio.LoopMode mode)? loopAction;

  List<FakeLoadRequest> get loadRequests => delegate.loadRequests;

  List<just_audio.LoopMode> get loopCalls => delegate.calls
      .where((call) => call.name == 'setLoopMode')
      .map((call) => call.arguments['mode']! as just_audio.LoopMode)
      .toList(growable: false);

  List<dynamic> get calls => delegate.calls;

  void emitLoopMode(just_audio.LoopMode mode) => delegate.emitLoopMode(mode);

  void emitPlayerState(just_audio.PlayerState state) =>
      delegate.emitPlayerState(state);

  void emitCurrentIndex(int? index) => delegate.emitCurrentIndex(index);

  @override
  Stream<just_audio.PlayerState> get playerStateStream =>
      delegate.playerStateStream;

  @override
  Stream<Duration> get positionStream => delegate.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream =>
      delegate.bufferedPositionStream;

  @override
  Stream<Duration?> get durationStream => delegate.durationStream;

  @override
  Stream<int?> get currentIndexStream => delegate.currentIndexStream;

  @override
  Stream<List<int>> get effectiveSequenceStream =>
      delegate.effectiveSequenceStream;

  @override
  Stream<double> get speedStream => delegate.speedStream;

  @override
  Stream<just_audio.LoopMode> get loopModeStream => delegate.loopModeStream;

  @override
  Stream<bool> get shuffleModeEnabledStream =>
      delegate.shuffleModeEnabledStream;

  @override
  Stream<just_audio.PlayerException> get errorStream => delegate.errorStream;

  @override
  Future<void> load(
    List<just_audio.AudioSource> sources, {
    required int initialIndex,
  }) => delegate.load(sources, initialIndex: initialIndex);

  @override
  Future<void> interruptLoad() => delegate.interruptLoad();

  @override
  Future<void> play() => delegate.play();

  @override
  Future<void> pause() => delegate.pause();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> seek(Duration position, {int? index}) =>
      delegate.seek(position, index: index);

  @override
  Future<void> setSpeed(double speed) => delegate.setSpeed(speed);

  @override
  Future<void> setLoopMode(just_audio.LoopMode mode) {
    delegate.setLoopMode(mode);
    return loopAction?.call(mode) ?? Future<void>.value();
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      delegate.setShuffleEnabled(enabled);

  @override
  Future<void> dispose() => delegate.dispose();
}
