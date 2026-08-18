// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/app/player_bootstrap.dart';
import 'package:vi_listen/features/player/application/playback_gateway.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_command_target.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import '../features/player/support/fake_playback_engine.dart';
import '../features/player/support/fake_player_clock.dart';

void main() {
  testWidgets(
    'dual-provider bridge keeps ownership and identity across widget changes',
    (tester) async {
      final harness = _BridgeHarness();
      final targetCubits = <PlayerCubit>[];
      final legacyCubits = <legacy_player.LegacyPlayerCubit>[];
      Widget? composedApp;

      void captureProviders(
        PlayerCubit target,
        legacy_player.LegacyPlayerCubit legacy,
      ) {
        targetCubits.add(target);
        legacyCubits.add(legacy);
      }

      try {
        await startPlayerApplication(
          app: MaterialApp(
            home: _BridgeProbe(onProvidersResolved: captureProviders),
          ),
          ensureInitialized: () {},
          initializeAudioService: ({required builder, required config}) async =>
              builder(),
          configureAudioSession: (_) async {},
          handlerFactory: harness.createHandler,
          gatewayFactory: harness.createGateway,
          playerCubitFactory: harness.createPlayerCubit,
          runApplication: (app) => composedApp = app,
        );

        await tester.pumpWidget(composedApp!);

        expect(targetCubits, isNotEmpty);
        expect(legacyCubits, isNotEmpty);
        final targetCubit = targetCubits.first;
        final legacyCubit = legacyCubits.first;

        expect(harness.gatewayTarget, same(harness.handler));
        expect(harness.cubitGateway, same(harness.gateway));
        expect(
          legacyCubit.state.presentation,
          legacy_player.LegacyPlayerPresentation.mini,
        );
        expect(legacyCubit.state.progress, .45);
        expect(legacyCubit.state.isPlaying, isTrue);
        _expectSinglePlaybackStack(harness);

        final targetStateBeforeLegacyMutation = targetCubit.state;
        await tester.tap(find.byKey(_legacyToggleKey));
        await tester.pump();

        expect(legacyCubit.state.isPlaying, isFalse);
        expect(targetCubit.state, same(targetStateBeforeLegacyMutation));
        expect(
          targetCubits.every((cubit) => identical(cubit, targetCubit)),
          isTrue,
        );
        expect(
          legacyCubits.every((cubit) => identical(cubit, legacyCubit)),
          isTrue,
        );
        _expectSinglePlaybackStack(harness);

        final capturesBeforeRebuild = targetCubits.length;
        await tester.tap(find.byKey(_rebuildKey));
        await tester.pump();

        expect(targetCubits.length, greaterThan(capturesBeforeRebuild));
        expect(
          targetCubits.every((cubit) => identical(cubit, targetCubit)),
          isTrue,
        );
        expect(
          legacyCubits.every((cubit) => identical(cubit, legacyCubit)),
          isTrue,
        );
        _expectSinglePlaybackStack(harness);

        final capturesBeforeRoute = targetCubits.length;
        await tester.tap(find.byKey(_pushRouteKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(_routeProbeKey), findsOneWidget);
        expect(targetCubits.length, greaterThan(capturesBeforeRoute));
        expect(
          targetCubits.every((cubit) => identical(cubit, targetCubit)),
          isTrue,
        );
        expect(
          legacyCubits.every((cubit) => identical(cubit, legacyCubit)),
          isTrue,
        );
        _expectSinglePlaybackStack(harness);

        final capturesDuringRoute = targetCubits.length;
        await tester.tap(find.byKey(_popRouteKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1000));

        expect(find.byKey(_routeProbeKey), findsNothing);
        expect(targetCubits.length, greaterThan(capturesDuringRoute));
        expect(
          targetCubits.every((cubit) => identical(cubit, targetCubit)),
          isTrue,
        );
        expect(
          legacyCubits.every((cubit) => identical(cubit, legacyCubit)),
          isTrue,
        );
        _expectSinglePlaybackStack(harness);
      } finally {
        final handler = harness.handler;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (handler != null) {
          await tester.runAsync(handler.dispose);
        }
      }
    },
  );
}

final class _BridgeHarness {
  AppAudioHandler? handler;
  PlaybackGateway? gateway;
  PlaybackGateway? cubitGateway;
  UiPlaybackCommandTarget? gatewayTarget;
  var handlerCount = 0;
  var engineCount = 0;
  var gatewayCount = 0;
  var targetCubitCount = 0;

  AppAudioHandler createHandler() {
    handlerCount += 1;
    final engine = FakePlaybackEngine();
    final clock = FakePlayerClock();
    final created = AppAudioHandler.production(
      engineFactory: () {
        engineCount += 1;
        return engine;
      },
      clockFactory: () => clock,
    );
    handler = created;
    return created;
  }

  PlaybackGateway createGateway(UiPlaybackCommandTarget target) {
    gatewayCount += 1;
    gatewayTarget = target;
    final created = UiPlaybackGatewayAdapter(target);
    gateway = created;
    return created;
  }

  PlayerCubit createPlayerCubit(PlaybackGateway gateway) {
    targetCubitCount += 1;
    cubitGateway = gateway;
    final created = PlayerCubit(gateway);
    return created;
  }
}

void _expectSinglePlaybackStack(_BridgeHarness harness) {
  expect(harness.handlerCount, 1);
  expect(harness.engineCount, 1);
  expect(harness.gatewayCount, 1);
  expect(harness.targetCubitCount, 1);
}

final class _BridgeProbe extends StatefulWidget {
  const _BridgeProbe({required this.onProvidersResolved});

  final void Function(
    PlayerCubit target,
    legacy_player.LegacyPlayerCubit legacy,
  )
  onProvidersResolved;

  @override
  State<_BridgeProbe> createState() => _BridgeProbeState();
}

final class _BridgeProbeState extends State<_BridgeProbe> {
  Future<void> _pushRoute(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            _BridgeRouteProbe(onProvidersResolved: widget.onProvidersResolved),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = context.read<PlayerCubit>();
    final legacy = context.read<legacy_player.LegacyPlayerCubit>();
    widget.onProvidersResolved(target, legacy);

    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            key: _legacyToggleKey,
            onPressed: legacy.togglePlayback,
            child: const Text('Toggle legacy playback'),
          ),
          ElevatedButton(
            key: _rebuildKey,
            onPressed: () => setState(() {}),
            child: const Text('Rebuild probe'),
          ),
          ElevatedButton(
            key: _pushRouteKey,
            onPressed: () => _pushRoute(context),
            child: const Text('Push route'),
          ),
        ],
      ),
    );
  }
}

final class _BridgeRouteProbe extends StatelessWidget {
  const _BridgeRouteProbe({required this.onProvidersResolved});

  final void Function(
    PlayerCubit target,
    legacy_player.LegacyPlayerCubit legacy,
  )
  onProvidersResolved;

  @override
  Widget build(BuildContext context) {
    final target = context.read<PlayerCubit>();
    final legacy = context.read<legacy_player.LegacyPlayerCubit>();
    onProvidersResolved(target, legacy);

    return Scaffold(
      key: _routeProbeKey,
      body: Center(
        child: ElevatedButton(
          key: _popRouteKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Pop route'),
        ),
      ),
    );
  }
}

const _legacyToggleKey = ValueKey('bridge-legacy-toggle');
const _rebuildKey = ValueKey('bridge-rebuild');
const _pushRouteKey = ValueKey('bridge-push-route');
const _routeProbeKey = ValueKey('bridge-route-probe');
const _popRouteKey = ValueKey('bridge-pop-route');
