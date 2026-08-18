// SPDX-License-Identifier: Apache-2.0

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/app/player_bootstrap.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_command_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import 'package:vi_listen/features/player/infrastructure/unavailable_playback_gateway.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import '../features/player/support/fake_playback_engine.dart';
import '../features/player/support/fake_player_clock.dart';

void main() {
  test('bootstrap order and composition providers are exact', () async {
    final calls = <String>[];
    var handlerCount = 0;
    var engineCount = 0;
    var adapterCount = 0;
    var cubitCount = 0;
    var runAppCount = 0;
    Widget? composedApp;
    AppAudioHandler? handler;
    PlayerCubit? cubit;
    FakePlaybackEngine? engine;
    FakePlayerClock? clock;

    await startPlayerApplication(
      app: const SizedBox.shrink(),
      ensureInitialized: () => calls.add('ensure'),
      initializeAudioService: ({required builder, required config}) async {
        calls.add('init:start');
        expect(config.androidNotificationChannelId, 'com.vilisten.playback');
        expect(config.androidNotificationChannelName, 'Đang phát');
        expect(config.androidStopForegroundOnPause, isFalse);

        final builtHandler = builder();
        calls.add('init:builder-returned');
        calls.add('init:complete');
        return builtHandler;
      },
      configureAudioSession: (configuration) async {
        calls.add('session:configure');
        expect(
          configuration.androidWillPauseWhenDucked,
          AudioSessionConfiguration.speech().androidWillPauseWhenDucked,
        );
        expect(
          configuration.avAudioSessionMode,
          AudioSessionConfiguration.speech().avAudioSessionMode,
        );
      },
      handlerFactory: () {
        calls.add('handler:create');
        handlerCount += 1;
        engine = FakePlaybackEngine();
        clock = FakePlayerClock();
        handler = AppAudioHandler.production(
          engineFactory: () {
            calls.add('engine:create');
            engineCount += 1;
            return engine!;
          },
          clockFactory: () => clock!,
        );
        return handler!;
      },
      gatewayFactory: (target) {
        calls.add('adapter:create');
        adapterCount += 1;
        return UiPlaybackGatewayAdapter(target);
      },
      playerCubitFactory: (gateway) {
        calls.add('cubit:create');
        cubitCount += 1;
        return cubit = PlayerCubit(gateway);
      },
      runApplication: (app) {
        calls.add('runApp');
        runAppCount += 1;
        composedApp = app;
      },
    );
    expect(calls, [
      'ensure',
      'init:start',
      'handler:create',
      'engine:create',
      'init:builder-returned',
      'init:complete',
      'session:configure',
      'adapter:create',
      'cubit:create',
      'runApp',
    ]);
    expect(handlerCount, 1);
    expect(engineCount, 1);
    expect(adapterCount, 1);
    expect(cubitCount, 1);
    expect(runAppCount, 1);
    expect(composedApp, isA<MultiBlocProvider>());

    await cubit!.close();
    await handler!.dispose();
  });

  testWidgets('composition smoke test provides target and legacy cubits', (
    tester,
  ) async {
    Widget? composedApp;

    await startPlayerApplication(
      app: const _CompositionProbe(),
      ensureInitialized: () {},
      initializeAudioService: ({required builder, required config}) =>
          Future<AppAudioHandler>.error(StateError('pre-handler failure')),
      configureAudioSession: (_) async {},
      handlerFactory: () => throw StateError('handler should not run'),
      failureMode: BootstrapFailureMode.unavailable,
      runApplication: (app) => composedApp = app,
    );

    await tester.pumpWidget(composedApp!);
  });

  test(
    'development bootstrap failure rethrows the original error and stack',
    () async {
      final error = StateError('audio service failed');
      final stackTrace = StackTrace.fromString('bootstrap sentinel stack');
      var initCount = 0;
      var handlerCount = 0;
      var adapterCount = 0;
      var cubitCount = 0;

      Object? caughtError;
      StackTrace? caughtStackTrace;
      try {
        await bootstrapPlayer(
          ensureInitialized: () {},
          initializeAudioService: ({required builder, required config}) {
            initCount += 1;
            return Future<AppAudioHandler>.error(error, stackTrace);
          },
          configureAudioSession: (_) async {},
          handlerFactory: () {
            handlerCount += 1;
            throw StateError('builder should not run');
          },
          gatewayFactory: (target) {
            adapterCount += 1;
            return UiPlaybackGatewayAdapter(target);
          },
          playerCubitFactory: (gateway) {
            cubitCount += 1;
            return PlayerCubit(gateway);
          },
        );
      } catch (caught, caughtStack) {
        caughtError = caught;
        caughtStackTrace = caughtStack;
      }

      expect(caughtError, same(error));
      expect(caughtStackTrace, same(stackTrace));
      expect(initCount, 1);
      expect(handlerCount, 0);
      expect(adapterCount, 0);
      expect(cubitCount, 0);
    },
  );

  test('production pre-handler failure injects unavailable playback', () async {
    final error = StateError('audio service unavailable');
    final stackTrace = StackTrace.fromString('pre-handler stack');
    var initCount = 0;
    var handlerCount = 0;
    var engineCount = 0;

    final result = await bootstrapPlayer(
      ensureInitialized: () {},
      initializeAudioService: ({required builder, required config}) {
        initCount += 1;
        return Future<AppAudioHandler>.error(error, stackTrace);
      },
      configureAudioSession: (_) async {},
      handlerFactory: () {
        handlerCount += 1;
        engineCount += 1;
        throw StateError('handler should not run');
      },
      failureMode: BootstrapFailureMode.unavailable,
    );

    expect(result.handler, isNull);
    expect(result.gateway, isA<UnavailablePlaybackGateway>());
    expect(initCount, 1);
    expect(handlerCount, 0);
    expect(engineCount, 0);

    final unavailableStream = result.gateway.snapshots;
    final snapshots = await Future.wait<PlaybackSnapshot>([
      unavailableStream.first,
      unavailableStream.first,
    ]);
    final firstSnapshot = snapshots[0];
    final secondSnapshot = snapshots[1];
    expect(firstSnapshot, secondSnapshot);
    expect(firstSnapshot.processingState, PlaybackProcessingState.error);
    expect(firstSnapshot.playing, isFalse);
    expect(firstSnapshot.failure?.code, 'bootstrapUnavailable');
    expect(firstSnapshot.failure?.isRecoverable, isFalse);

    await _expectUnavailable(
      'loadQueue',
      () => result.gateway.loadQueue(const <PlayerItem>[]),
    );
    await _expectUnavailable('play', result.gateway.play);
    await _expectUnavailable('pause', result.gateway.pause);
    await _expectUnavailable('stop', result.gateway.stop);
    await _expectUnavailable('seek', () => result.gateway.seek(Duration.zero));
    await _expectUnavailable(
      'skipBy',
      () => result.gateway.skipBy(Duration.zero),
    );
    await _expectUnavailable('next', result.gateway.next);
    await _expectUnavailable('previous', result.gateway.previous);
    await _expectUnavailable('setSpeed', () => result.gateway.setSpeed(1.0));
    await _expectUnavailable(
      'setRepeatMode',
      () => result.gateway.setRepeatMode(PlayerRepeatMode.off),
    );
    await _expectUnavailable(
      'setShuffleEnabled',
      () => result.gateway.setShuffleEnabled(false),
    );
    await _expectUnavailable('retry', result.gateway.retry);

    await pumpEventQueue();
    expect(
      result.playerCubit.state.playback.failure?.code,
      'bootstrapUnavailable',
    );
    await result.playerCubit.close();
  });

  test(
    'production ensureInitialized failure injects unavailable playback',
    () async {
      final error = StateError('binding unavailable');
      final stackTrace = StackTrace.fromString('binding sentinel stack');
      var initCount = 0;
      var handlerCount = 0;
      var engineCount = 0;

      final result = await bootstrapPlayer(
        ensureInitialized: () => Error.throwWithStackTrace(error, stackTrace),
        initializeAudioService: ({required builder, required config}) {
          initCount += 1;
          return Future<AppAudioHandler>.error(
            StateError('audio service should not run'),
          );
        },
        configureAudioSession: (_) async {},
        handlerFactory: () {
          handlerCount += 1;
          engineCount += 1;
          throw StateError('handler should not run');
        },
        failureMode: BootstrapFailureMode.unavailable,
      );

      expect(result.handler, isNull);
      expect(result.gateway, isA<UnavailablePlaybackGateway>());
      expect(initCount, 0);
      expect(handlerCount, 0);
      expect(engineCount, 0);
      await result.playerCubit.close();
    },
  );

  test('failure after handler creation remains fail-fast', () async {
    final error = StateError('session failed');
    final stackTrace = StackTrace.fromString('post-handler stack');
    AppAudioHandler? handler;
    var handlerCount = 0;
    var engineCount = 0;
    var configureCount = 0;

    Object? caughtError;
    StackTrace? caughtStackTrace;
    try {
      await bootstrapPlayer(
        ensureInitialized: () {},
        initializeAudioService: ({required builder, required config}) async =>
            builder(),
        configureAudioSession: (_) {
          configureCount += 1;
          return Future<void>.error(error, stackTrace);
        },
        handlerFactory: () {
          handlerCount += 1;
          final engine = FakePlaybackEngine();
          final clock = FakePlayerClock();
          handler = AppAudioHandler.production(
            engineFactory: () {
              engineCount += 1;
              return engine;
            },
            clockFactory: () => clock,
          );
          return handler!;
        },
        failureMode: BootstrapFailureMode.unavailable,
      );
    } catch (caught, caughtStack) {
      caughtError = caught;
      caughtStackTrace = caughtStack;
    }

    expect(caughtError, same(error));
    expect(caughtStackTrace, same(stackTrace));
    expect(configureCount, 1);
    expect(handlerCount, 1);
    expect(engineCount, 1);
    await handler!.dispose();
  });
}

final class _CompositionProbe extends StatelessWidget {
  const _CompositionProbe();

  @override
  Widget build(BuildContext context) {
    context.read<PlayerCubit>();
    context.read<legacy_player.LegacyPlayerCubit>();
    return const SizedBox.shrink();
  }
}

Future<void> _expectUnavailable(
  String command,
  Future<void> Function() operation,
) async {
  Object? caughtError;
  try {
    await operation();
  } catch (error) {
    caughtError = error;
  }

  expect(
    caughtError,
    isA<PlayerCommandFailure>()
        .having((failure) => failure.code, 'code', 'commandUnavailable')
        .having((failure) => failure.command, 'command', command),
  );
}
