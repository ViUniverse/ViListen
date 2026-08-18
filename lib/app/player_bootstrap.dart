// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/playback_gateway.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/player_audio_service_config.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_command_target.dart';
import 'package:vi_listen/features/player/infrastructure/ui_playback_gateway_adapter.dart';
import 'package:vi_listen/features/player/infrastructure/unavailable_playback_gateway.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;

enum BootstrapFailureMode { failFast, unavailable }

typedef AudioServiceInitializer =
    Future<AppAudioHandler> Function({
      required AppAudioHandler Function() builder,
      required audio_service.AudioServiceConfig config,
    });

typedef AudioSessionConfigurator =
    Future<void> Function(AudioSessionConfiguration configuration);

typedef PlayerHandlerFactory = AppAudioHandler Function();

typedef PlaybackGatewayFactory =
    PlaybackGateway Function(UiPlaybackCommandTarget target);

typedef PlayerCubitFactory = PlayerCubit Function(PlaybackGateway gateway);

/// The objects composed by the application root before the first frame.
final class PlayerBootstrapResult {
  const PlayerBootstrapResult({
    required this.gateway,
    required this.playerCubit,
    this.handler,
  });

  final PlaybackGateway gateway;
  final PlayerCubit playerCubit;
  final AppAudioHandler? handler;
}

/// Composes the player without touching a platform plugin in unit tests.
Future<PlayerBootstrapResult> bootstrapPlayer({
  required VoidCallback ensureInitialized,
  required AudioServiceInitializer initializeAudioService,
  required AudioSessionConfigurator configureAudioSession,
  required PlayerHandlerFactory handlerFactory,
  PlaybackGatewayFactory gatewayFactory = _createUiGateway,
  PlayerCubitFactory playerCubitFactory = _createPlayerCubit,
  BootstrapFailureMode failureMode = BootstrapFailureMode.failFast,
}) async {
  var builderInvoked = false;
  AppAudioHandler? handler;

  AppAudioHandler createHandler() {
    builderInvoked = true;
    final created = handlerFactory();
    handler = created;
    return created;
  }

  try {
    ensureInitialized();

    final initializedHandler = await initializeAudioService(
      builder: createHandler,
      config: createPlayerAudioServiceConfig(),
    );
    handler ??= initializedHandler;

    await configureAudioSession(const AudioSessionConfiguration.speech());

    final createdHandler = handler;
    if (createdHandler == null) {
      throw StateError('AudioService.init returned no handler.');
    }

    final gateway = gatewayFactory(createdHandler);
    return PlayerBootstrapResult(
      handler: createdHandler,
      gateway: gateway,
      playerCubit: playerCubitFactory(gateway),
    );
  } catch (error, stackTrace) {
    // Once the builder has run, a handler/player may already exist. Falling
    // back then would create an ambiguous second playback stack, so this
    // stage always preserves fail-fast behavior.
    if (failureMode == BootstrapFailureMode.failFast ||
        builderInvoked ||
        handler != null) {
      Error.throwWithStackTrace(error, stackTrace);
    }

    final gateway = UnavailablePlaybackGateway();
    return PlayerBootstrapResult(
      gateway: gateway,
      playerCubit: playerCubitFactory(gateway),
    );
  }
}

/// Production outer seam. It keeps [runApp] after the complete bootstrap.
Future<void> startPlayerApplication({
  required Widget app,
  VoidCallback? ensureInitialized,
  AudioServiceInitializer? initializeAudioService,
  AudioSessionConfigurator? configureAudioSession,
  PlayerHandlerFactory? handlerFactory,
  PlaybackGatewayFactory? gatewayFactory,
  PlayerCubitFactory? playerCubitFactory,
  void Function(Widget app)? runApplication,
  BootstrapFailureMode failureMode = kReleaseMode
      ? BootstrapFailureMode.unavailable
      : BootstrapFailureMode.failFast,
}) async {
  final result = await bootstrapPlayer(
    ensureInitialized: ensureInitialized ?? _ensureInitialized,
    initializeAudioService: initializeAudioService ?? _initializeAudioService,
    configureAudioSession: configureAudioSession ?? _configureAudioSession,
    handlerFactory: handlerFactory ?? AppAudioHandler.production,
    gatewayFactory: gatewayFactory ?? _createUiGateway,
    playerCubitFactory: playerCubitFactory ?? _createPlayerCubit,
    failureMode: failureMode,
  );

  (runApplication ?? runApp)(
    MultiBlocProvider(
      providers: [
        BlocProvider<PlayerCubit>(create: (_) => result.playerCubit),
        // TODO(PLR-110): Remove the temporary legacy provider after migration.
        BlocProvider<legacy_player.LegacyPlayerCubit>(
          create: (_) => legacy_player.LegacyPlayerCubit(),
        ),
      ],
      child: app,
    ),
  );
}

void _ensureInitialized() {
  WidgetsFlutterBinding.ensureInitialized();
}

Future<AppAudioHandler> _initializeAudioService({
  required AppAudioHandler Function() builder,
  required audio_service.AudioServiceConfig config,
}) => audio_service.AudioService.init<AppAudioHandler>(
  builder: builder,
  config: config,
);

Future<void> _configureAudioSession(
  AudioSessionConfiguration configuration,
) async {
  final session = await AudioSession.instance;
  await session.configure(configuration);
}

PlaybackGateway _createUiGateway(UiPlaybackCommandTarget target) =>
    UiPlaybackGatewayAdapter(target);

PlayerCubit _createPlayerCubit(PlaybackGateway gateway) => PlayerCubit(gateway);
