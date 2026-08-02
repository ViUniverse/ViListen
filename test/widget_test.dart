import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/presentation/cubit/player_cubit.dart';
import 'package:ten_project_cua_ban/main.dart';

Widget buildSubject() =>
    BlocProvider(create: (_) => LegacyPlayerCubit(), child: const MyApp());

void main() {
  testWidgets('mini player controls shared playback state', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    expect(find.text('The English We Speak: On their toes'), findsOneWidget);
    expect(find.byTooltip('Tạm dừng'), findsOneWidget);

    await tester.tap(find.byTooltip('Tạm dừng'));
    await tester.pump();

    expect(find.byTooltip('Phát'), findsOneWidget);
  });

  testWidgets('opens expanded player and closes back to mini player', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());

    await tester.tap(find.byKey(const ValueKey('mini-player')));
    await tester.pumpAndSettle();

    expect(find.text('Đang nghe'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(Hero, skipOffstage: false), findsWidgets);

    await tester.drag(
      find.bySemanticsLabel('Kéo lời thoại để mở rộng'),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bottom-player')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sheet-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
  });

  testWidgets('swipes the expanded player down to return to mini player', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.tap(find.byKey(const ValueKey('mini-player')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('expanded-player-dismiss-region')),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
  });
}
