// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/presentation/cubit/player_cubit.dart'
    as legacy_player;
import 'package:vi_listen/features/player/presentation/expanded_player_screen.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_host.dart';
import '../../support/playback_snapshot_builder.dart';
import '../../support/player_test_data.dart';
import '../../support/player_widget_harness.dart';

void main() {
  for (final processingState in [
    PlaybackProcessingState.loading,
    PlaybackProcessingState.ready,
    PlaybackProcessingState.error,
    PlaybackProcessingState.completed,
  ]) {
    testWidgets(
      'shows mini when an item exists in ${processingState.name} state',
      (tester) async {
        final harness = PlayerWidgetHarness();
        try {
          await _pumpHost(tester, harness);

          final item = testPlayerItem();
          await _emitSnapshot(
            tester,
            harness,
            buildPlaybackSnapshot(
              currentItem: item,
              processingState: processingState,
              duration: const Duration(minutes: 1),
              position: processingState == PlaybackProcessingState.completed
                  ? const Duration(minutes: 1)
                  : Duration.zero,
              failure: processingState == PlaybackProcessingState.error
                  ? const PlayerFailure(
                      code: 'network',
                      message: 'Network unavailable.',
                      isRecoverable: true,
                      itemId: 'track-1',
                    )
                  : null,
            ),
          );

          expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
        } finally {
          await harness.dispose(tester);
        }
      },
    );
  }

  testWidgets('hides mini while target snapshot is idle', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpHost(tester, harness);

      expect(find.byKey(const ValueKey('mini-player')), findsNothing);
      expect(harness.targetCubit.state.playback, same(PlaybackSnapshot.idle));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('hides mini after a stop snapshot', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpHost(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);

      await _emitSnapshot(tester, harness, PlaybackSnapshot.idle);

      expect(find.byKey(const ValueKey('mini-player')), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'rapid taps push one route and do not mutate player navigation state',
    (tester) async {
      final harness = PlayerWidgetHarness();
      final observer = _RecordingNavigatorObserver();
      try {
        await _pumpHost(tester, harness, observer: observer);

        final activeSnapshot = buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
          playing: false,
        );
        await _emitSnapshot(tester, harness, activeSnapshot);

        expect(
          harness.legacyCubit.state.presentation,
          legacy_player.LegacyPlayerPresentation.mini,
        );

        final miniCenter = tester.getCenter(
          find.byKey(const ValueKey('mini-player')),
        );
        await tester.tapAt(miniCenter);
        await tester.tapAt(miniCenter);
        await tester.pumpAndSettle();

        expect(
          observer.pushedRoutes.whereType<ExpandedPlayerRoute>(),
          hasLength(1),
        );
        expect(find.byType(ExpandedPlayerScreen), findsOneWidget);
        expect(harness.targetCubit.state.playback, same(activeSnapshot));
        expect(
          harness.legacyCubit.state.presentation,
          legacy_player.LegacyPlayerPresentation.mini,
        );

        Navigator.of(tester.element(find.byType(ExpandedPlayerScreen))).pop();
        await tester.pumpAndSettle();

        expect(harness.targetCubit.state.playback, same(activeSnapshot));
        expect(
          harness.legacyCubit.state.presentation,
          legacy_player.LegacyPlayerPresentation.mini,
        );
      } finally {
        await harness.dispose(tester);
      }
    },
  );
}

Future<void> _emitSnapshot(
  WidgetTester tester,
  PlayerWidgetHarness harness,
  PlaybackSnapshot snapshot,
) async {
  harness.gateway.emit(snapshot);
  await tester.runAsync(() async {
    await Future<void>.microtask(() {});
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pump();
}

Future<void> _pumpHost(
  WidgetTester tester,
  PlayerWidgetHarness harness, {
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    harness.wrap(
      MaterialApp(
        navigatorObservers: [?observer],
        home: const Scaffold(
          body: Stack(children: [SizedBox.expand(), PlayerHost()]),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}
