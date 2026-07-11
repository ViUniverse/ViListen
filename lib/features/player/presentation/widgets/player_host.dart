import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ten_project_cua_ban/features/player/presentation/cubit/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/presentation/expanded_player_screen.dart';
import 'package:ten_project_cua_ban/features/player/presentation/widgets/mini_player.dart';

class PlayerHost extends StatelessWidget {
  const PlayerHost({super.key});

  Future<void> _openExpandedPlayer(BuildContext context) async {
    final cubit = context.read<PlayerCubit>();
    cubit.expand();
    await Navigator.of(context).push<void>(ExpandedPlayerRoute());
    cubit.minimize();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (previous, current) =>
        previous.presentation != current.presentation,
    builder: (context, state) {
      if (state.presentation == PlayerPresentation.hidden) {
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
