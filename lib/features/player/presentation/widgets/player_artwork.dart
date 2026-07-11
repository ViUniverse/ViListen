import 'dart:math' as math;

import 'package:flutter/material.dart';

const playerArtworkHeroTag = 'now-playing-artwork';

class PlayerArtworkHero extends StatelessWidget {
  const PlayerArtworkHero({
    super.key,
    required this.size,
    required this.radius,
  });

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => Hero(
    tag: playerArtworkHeroTag,
    createRectTween: (begin, end) =>
        MaterialRectArcTween(begin: begin, end: end),
    child: PlayerArtwork(size: size, radius: radius),
  );
}

class PlayerArtwork extends StatelessWidget {
  const PlayerArtwork({super.key, required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x4df2542c),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Stack(
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
    ),
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
