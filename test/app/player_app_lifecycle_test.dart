// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/app/player_bootstrap.dart';
import 'package:vi_listen/features/player/application/playback_gateway.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_command_target.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import '../features/player/support/fake_playback_engine.dart';
import '../features/player/support/fake_player_clock.dart';
import '../features/player/support/player_test_data.dart';

void main() {
  testWidgets(
    'lifecycle-only events do not issue playback commands through composition',
    (tester) async {
      final harness = _AppLifecycleHarness();
      try {
        await _mountApp(tester, harness);
        await _loadPlaying(tester, harness);

        final engineCallsBeforeLifecycle = harness.playbackEngine.calls.length;
        final commandsBeforeLifecycle = harness.observedCommands.length;

        for (final lifecycleState in <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(lifecycleState);
          await tester.pump();

          expect(
            harness.playbackEngine.calls.length,
            engineCallsBeforeLifecycle,
          );
          expect(harness.observedCommands.length, commandsBeforeLifecycle);
          expect(harness.cubit.state.playing, isTrue);
          _expectSinglePlaybackStack(harness);
        }
      } finally {
        await _disposeApp(tester, harness);
      }
    },
  );

  testWidgets(
    'remote pause works in background and foreground renders latest snapshot',
    (tester) async {
      final harness = _AppLifecycleHarness();
      try {
        await _mountApp(tester, harness);
        await _loadPlaying(tester, harness);

        final engineCallsBeforeBackground = harness.playbackEngine.calls.length;
        final commandsBeforeBackground = harness.observedCommands.length;

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        // The lifecycle event itself must not become a Pause command.
        expect(harness.playbackEngine.callCountFor('pause'), 0);
        expect(
          harness.playbackEngine.calls.length,
          engineCallsBeforeBackground,
        );
        expect(harness.observedCommands.length, commandsBeforeBackground);

        // BaseAudioHandler.pause is the remote callback seam.
        final remotePause = harness.activeHandler.pause();
        await tester.pump();

        expect(harness.playbackEngine.callCountFor('pause'), 1);
        expect(harness.observedCommands.skip(commandsBeforeBackground), [
          (command: 'pause', source: CommandSource.systemRemote),
        ]);

        harness.playbackEngine.emitPlayerState(
          just_audio.PlayerState(false, just_audio.ProcessingState.ready),
        );
        harness.playbackEngine.emitPosition(const Duration(seconds: 37));
        harness.playerClock.advance(const Duration(seconds: 1));
        await remotePause;
        await tester.pump();

        expect(harness.cubit.state.currentItem?.id, 'lifecycle-track');
        expect(harness.cubit.state.playing, isFalse);
        expect(harness.cubit.state.position, const Duration(seconds: 37));

        final engineCallsBeforeResume = harness.playbackEngine.calls.length;
        final commandsBeforeResume = harness.observedCommands.length;
        final handlerCountBeforeResume = harness.handlerCount;
        final engineCountBeforeResume = harness.engineCount;
        final cubitCountBeforeResume = harness.cubitCount;

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(find.text('lifecycle-track|false|ready|37000'), findsOneWidget);
        expect(harness.playbackEngine.calls.length, engineCallsBeforeResume);
        expect(harness.observedCommands.length, commandsBeforeResume);
        expect(harness.handlerCount, handlerCountBeforeResume);
        expect(harness.engineCount, engineCountBeforeResume);
        expect(harness.cubitCount, cubitCountBeforeResume);
        _expectSinglePlaybackStack(harness);
      } finally {
        await _disposeApp(tester, harness);
      }
    },
  );
}

Future<void> _mountApp(
  WidgetTester tester,
  _AppLifecycleHarness harness,
) async {
  Widget? composedApp;
  await startPlayerApplication(
    app: const MaterialApp(home: _LifecycleProbe()),
    ensureInitialized: () {},
    initializeAudioService: ({required builder, required config}) async =>
        builder(),
    configureAudioSession: (_) async {},
    handlerFactory: harness.createHandler,
    gatewayFactory: harness.createGateway,
    playerCubitFactory: harness.createPlayerCubit,
    runApplication: (app) => composedApp = app,
  );

  expect(composedApp, isNotNull);
  await tester.pumpWidget(composedApp!);
  await tester.pump();
}

Future<void> _loadPlaying(
  WidgetTester tester,
  _AppLifecycleHarness harness,
) async {
  final load = harness.activeHandler.handleLoadQueue(
    [testPlayerItem(id: 'lifecycle-track')],
    0,
    false,
    CommandSource.ui,
  );
  await tester.pump();
  harness.playbackEngine.loadRequests.single.complete();
  harness.playbackEngine.emitDuration(const Duration(minutes: 1));
  harness.playbackEngine.emitPosition(Duration.zero);
  await load;
  await tester.pump();

  harness.playbackEngine.emitPlayerState(
    just_audio.PlayerState(true, just_audio.ProcessingState.ready),
  );
  await tester.pump();
}

Future<void> _disposeApp(
  WidgetTester tester,
  _AppLifecycleHarness harness,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final handler = harness.handler;
  if (handler != null) {
    await tester.runAsync(handler.dispose);
  }
}

void _expectSinglePlaybackStack(_AppLifecycleHarness harness) {
  expect(harness.handlerCount, 1);
  expect(harness.engineCount, 1);
  expect(harness.gatewayCount, 1);
  expect(harness.cubitCount, 1);
}

final class _AppLifecycleHarness {
  AppAudioHandler? handler;
  FakePlaybackEngine? engine;
  FakePlayerClock? clock;
  PlaybackGateway? gateway;
  PlayerCubit? playerCubit;

  final List<({String command, CommandSource source})> observedCommands =
      <({String command, CommandSource source})>[];

  int handlerCount = 0;
  int engineCount = 0;
  int gatewayCount = 0;
  int cubitCount = 0;

  AppAudioHandler get activeHandler => handler!;
  FakePlaybackEngine get playbackEngine => engine!;
  FakePlayerClock get playerClock => clock!;
  PlayerCubit get cubit => playerCubit!;

  AppAudioHandler createHandler() {
    handlerCount += 1;
    final createdEngine = FakePlaybackEngine();
    final createdClock = FakePlayerClock();
    engine = createdEngine;
    clock = createdClock;
    engineCount += 1;
    final createdHandler = AppAudioHandler.production(
      engineFactory: () => createdEngine,
      clockFactory: () => createdClock,
      commandObserver: (command, source) {
        observedCommands.add((command: command, source: source));
      },
    );
    handler = createdHandler;
    return createdHandler;
  }

  PlaybackGateway createGateway(UiPlaybackCommandTarget target) {
    gatewayCount += 1;
    return gateway = UiPlaybackGatewayAdapter(target);
  }

  PlayerCubit createPlayerCubit(PlaybackGateway playbackGateway) {
    cubitCount += 1;
    return playerCubit = PlayerCubit(playbackGateway);
  }
}

final class _LifecycleProbe extends StatelessWidget {
  const _LifecycleProbe();

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    builder: (context, state) => Text(
      '${state.currentItem?.id}|'
      '${state.playing}|'
      '${state.playback.processingState.name}|'
      '${state.position.inMilliseconds}',
    ),
  );
}
