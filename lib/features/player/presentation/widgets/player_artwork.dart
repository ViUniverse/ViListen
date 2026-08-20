// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/application/player_state.dart';
import 'player_artwork_image_provider.dart'
    if (dart.library.io) 'player_artwork_image_provider_io.dart'
    if (dart.library.js_interop) 'player_artwork_image_provider_web.dart'
    as artwork_image_provider;

const playerArtworkHeroTag = 'now-playing-artwork';

typedef PlayerArtworkImageProviderResolver =
    ImageProvider<Object> Function(Uri uri);

class PlayerArtworkHero extends StatelessWidget {
  const PlayerArtworkHero({
    super.key,
    required this.size,
    required this.radius,
    this.imageProviderResolver,
  });

  final double size;
  final double radius;
  final PlayerArtworkImageProviderResolver? imageProviderResolver;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PlayerCubit, PlayerState, Uri?>(
        selector: (state) => state.currentItem?.artUri,
        builder: (context, artUri) => Hero(
          tag: playerArtworkHeroTag,
          createRectTween: (begin, end) =>
              MaterialRectArcTween(begin: begin, end: end),
          child: PlayerArtwork(
            size: size,
            radius: radius,
            artUri: artUri,
            imageProviderResolver: imageProviderResolver,
          ),
        ),
      );
}

class PlayerArtwork extends StatefulWidget {
  const PlayerArtwork({
    super.key,
    required this.size,
    required this.radius,
    this.artUri,
    this.imageProviderResolver,
  });

  final double size;
  final double radius;
  final Uri? artUri;
  final PlayerArtworkImageProviderResolver? imageProviderResolver;

  @override
  State<PlayerArtwork> createState() => _PlayerArtworkState();
}

class _PlayerArtworkState extends State<PlayerArtwork> {
  ImageProvider<Object>? _provider;

  @override
  void initState() {
    super.initState();
    _resolveProvider();
  }

  @override
  void didUpdateWidget(covariant PlayerArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artUri != widget.artUri) {
      _resolveProvider();
    }
  }

  void _resolveProvider() {
    final uri = widget.artUri;
    if (uri == null) {
      _provider = null;
      return;
    }

    try {
      _provider =
          (widget.imageProviderResolver ??
          artwork_image_provider.resolvePlayerArtworkImageProvider)(uri);
    } on Object {
      _provider = null;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    width: widget.size,
    height: widget.size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(widget.radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x4df2542c),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: _provider == null
        ? const _ArtworkPlaceholder()
        : Image(
            key: ValueKey<String>('player-artwork-image-${widget.artUri}'),
            image: _provider!,
            fit: BoxFit.cover,
            gaplessPlayback: false,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return const _ArtworkPlaceholder();
            },
            errorBuilder: (context, error, stackTrace) =>
                const _ArtworkPlaceholder(),
          ),
  );
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey<String>('player-artwork-placeholder'),
    fit: StackFit.expand,
    children: [
      const CustomPaint(painter: _BookPainter()),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xfff2542c).withValues(alpha: .86),
              const Color(0xffec4899).withValues(alpha: .78),
            ],
          ),
        ),
      ),
    ],
  );
}

class _BookPainter extends CustomPainter {
  const _BookPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xff14101d), Color(0xff6f2839), Color(0xffb54f5f)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [Colors.white.withValues(alpha: .72), Colors.transparent],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .48, size.height * .43),
              radius: size.width * .65,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * .48, size.height * .43),
      size.width * .65,
      glow,
    );
    final bookPaint = Paint()..color = const Color(0xffffe8c6);
    final left = Path()
      ..moveTo(size.width * .08, size.height * .62)
      ..quadraticBezierTo(
        size.width * .28,
        size.height * .48,
        size.width * .49,
        size.height * .59,
      )
      ..lineTo(size.width * .49, size.height * .87)
      ..quadraticBezierTo(
        size.width * .28,
        size.height * .74,
        size.width * .08,
        size.height * .87,
      )
      ..close();
    final right = Path()
      ..moveTo(size.width * .51, size.height * .59)
      ..quadraticBezierTo(
        size.width * .73,
        size.height * .48,
        size.width * .94,
        size.height * .62,
      )
      ..lineTo(size.width * .94, size.height * .87)
      ..quadraticBezierTo(
        size.width * .73,
        size.height * .74,
        size.width * .51,
        size.height * .87,
      )
      ..close();
    canvas.drawPath(left, bookPaint);
    canvas.drawPath(right, bookPaint);
    final linePaint = Paint()
      ..color = const Color(0xffbf6b76).withValues(alpha: .55)
      ..strokeWidth = 2;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.66 + i * .045);
      canvas.drawLine(
        Offset(size.width * .17, y),
        Offset(size.width * .41, y - 4),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width * .58, y - 4),
        Offset(size.width * .84, y),
        linePaint,
      );
    }
    final dot = Paint()..color = Colors.white.withValues(alpha: .75);
    final random = math.Random(12);
    for (var i = 0; i < 45; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height * .62,
        ),
        random.nextDouble() * 2.7 + .5,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
