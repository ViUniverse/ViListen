// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'package:vi_listen/features/player/presentation/expanded_player_screen.dart';
import 'package:vi_listen/features/player/presentation/widgets/mini_player.dart';

class PlayerHost extends StatefulWidget {
  const PlayerHost({super.key});

  @override
  State<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends State<PlayerHost> {
  bool _expandedRouteOpen = false;

  Future<void> _openExpandedPlayer(BuildContext context) async {
    if (_expandedRouteOpen) {
      return;
    }

    _expandedRouteOpen = true;
    try {
      await Navigator.of(context).push<void>(ExpandedPlayerRoute());
    } finally {
      _expandedRouteOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (previous, current) =>
        (previous.currentItem == null) != (current.currentItem == null),
    builder: (context, state) {
      if (state.currentItem == null) {
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
