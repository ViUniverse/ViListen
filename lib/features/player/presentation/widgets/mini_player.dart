import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ten_project_cua_ban/features/player/presentation/cubit/player_cubit.dart';
import 'package:ten_project_cua_ban/features/player/presentation/widgets/player_artwork.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (previous, current) =>
        previous.progress != current.progress ||
        previous.isPlaying != current.isPlaying ||
        previous.speedIndex != current.speedIndex,
    builder: (context, state) {
      final cubit = context.read<PlayerCubit>();
      return Semantics(
        button: true,
        label: 'Mở trình phát The English We Speak: On their toes',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              key: const ValueKey('mini-player'),
              height: 72,
              padding: const EdgeInsets.fromLTRB(13, 0, 12, 0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xfff2542c), Color(0xffec4899)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x19000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .95),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Row(
                  children: [
                    const PlayerArtworkHero(size: 44, radius: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'The English We Speak: On their toes',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'BBC Learning English • 2m 39s',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xff64748b),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: state.progress,
                              minHeight: 2,
                              color: const Color(0xfff2542c),
                              backgroundColor: const Color(0xffe2e8f0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: state.isPlaying ? 'Tạm dừng' : 'Phát',
                      onPressed: cubit.togglePlayback,
                      icon: Icon(
                        state.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: const Color(0xfff2542c),
                        size: 29,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
