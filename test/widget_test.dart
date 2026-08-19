// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import 'package:vi_listen/main.dart';
import 'features/player/support/player_widget_harness.dart';

PlayerWidgetHarness buildSubject() => PlayerWidgetHarness();

void main() {
  testWidgets('mini player controls shared playback state', (tester) async {
    final harness = buildSubject();
    try {
      await tester.pumpWidget(harness.wrap(const MyApp()));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
      expect(find.text('The English We Speak: On their toes'), findsOneWidget);
      expect(find.byTooltip('Tạm dừng'), findsOneWidget);

      await tester.tap(find.byTooltip('Tạm dừng'));
      await tester.pump();

      expect(find.byTooltip('Phát'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('opens expanded player and closes back to mini player', (
    tester,
  ) async {
    final harness = buildSubject();
    try {
      await tester.pumpWidget(harness.wrap(const MyApp()));

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
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('swipes the expanded player down to return to mini player', (
    tester,
  ) async {
    final harness = buildSubject();
    try {
      await tester.pumpWidget(harness.wrap(const MyApp()));
      await tester.tap(find.byKey(const ValueKey('mini-player')));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('expanded-player-dismiss-region')),
        const Offset(0, 420),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('dual-provider widget harness renders app without plugins', (
    tester,
  ) async {
    final harness = buildSubject();
    try {
      await tester.pumpWidget(harness.wrap(const MyApp()));

      final context = tester.element(find.byType(NavigationBar));
      final target = context.read<PlayerCubit>();
      final legacy = context.read<legacy_player.LegacyPlayerCubit>();

      expect(target, same(harness.targetCubit));
      expect(legacy, same(harness.legacyCubit));
      expect(target.state.playback, same(PlaybackSnapshot.idle));
      expect(target.state.currentItem, isNull);
      expect(target.state.playing, isFalse);
      expect(
        legacy.state.presentation,
        legacy_player.LegacyPlayerPresentation.mini,
      );
      expect(legacy.state.progress, .45);
      expect(legacy.state.isPlaying, isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });
}
