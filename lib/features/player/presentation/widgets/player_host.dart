// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart';
import 'package:vi_listen/features/player/presentation/expanded_player_screen.dart';
import 'package:vi_listen/features/player/presentation/widgets/mini_player.dart';

class PlayerHost extends StatelessWidget {
  const PlayerHost({super.key});

  Future<void> _openExpandedPlayer(BuildContext context) async {
    final cubit = context.read<LegacyPlayerCubit>();
    cubit.expand();
    await Navigator.of(context).push<void>(ExpandedPlayerRoute());
    cubit.minimize();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LegacyPlayerCubit, LegacyPlayerState>(
        buildWhen: (previous, current) =>
            previous.presentation != current.presentation,
        builder: (context, state) {
          if (state.presentation == LegacyPlayerPresentation.hidden) {
            return const SizedBox.shrink();
          }
          return Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: MiniPlayer(onOpen: () => _openExpandedPlayer(context)),
          );
        },
      );
}
