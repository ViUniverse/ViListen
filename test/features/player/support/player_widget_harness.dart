// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import 'fake_playback_gateway.dart';

final class PlayerWidgetHarness {
  PlayerWidgetHarness()
    : gateway = FakePlaybackGateway(initialSnapshot: PlaybackSnapshot.idle),
      legacyCubit = legacy_player.LegacyPlayerCubit() {
    targetCubit = PlayerCubit(gateway);
  }

  final FakePlaybackGateway gateway;
  late final PlayerCubit targetCubit;
  final legacy_player.LegacyPlayerCubit legacyCubit;

  Widget wrap(Widget child) => MultiBlocProvider(
    providers: [
      BlocProvider<PlayerCubit>.value(value: targetCubit),
      BlocProvider<legacy_player.LegacyPlayerCubit>.value(value: legacyCubit),
    ],
    child: child,
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.runAsync(() async {
      await targetCubit.close();
      await legacyCubit.close();
      await gateway.dispose();
    });
  }
}
