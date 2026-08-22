// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/expanded_player_screen.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_artwork.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_control_dock.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';
import '../support/player_widget_harness.dart';

void main() {
  testWidgets('renders metadata from the confirmed player snapshot', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpExpandedPlayer(tester, harness);

      final item = testPlayerItem(
        title: 'Episode A',
        artist: 'Author A',
        duration: const Duration(minutes: 10),
      );
      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.ready,
          duration: const Duration(minutes: 4, seconds: 12),
        ),
      );

      expect(find.text('Episode A'), findsOneWidget);
      expect(find.text('Author A'), findsOneWidget);
      expect(find.text('4m 12s'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Ảnh bìa\s*Episode A')),
        findsOneWidget,
      );
      expect(find.byType(PlayerControlDock), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byType(Hero), findsWidgets);
      expect(find.text('The English We Speak:\nOn their toes'), findsNothing);
      expect(find.text('BBC Learning English'), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('updates metadata when the current item changes', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpExpandedPlayer(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(
            title: 'Episode A',
            artist: 'Author A',
            duration: const Duration(minutes: 4, seconds: 12),
          ),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      expect(find.text('Episode A'), findsOneWidget);
      expect(find.text('4m 12s'), findsOneWidget);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(
            id: 'track-2',
            title: 'Episode B',
            artist: 'Author B',
            duration: const Duration(minutes: 7, seconds: 3),
          ),
          processingState: PlaybackProcessingState.ready,
        ),
      );

      expect(find.text('Episode A'), findsNothing);
      expect(find.text('Author A'), findsNothing);
      expect(find.text('4m 12s'), findsNothing);
      expect(find.text('Episode B'), findsOneWidget);
      expect(find.text('Author B'), findsOneWidget);
      expect(find.text('7m 3s'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Ảnh bìa\s*Episode B')),
        findsOneWidget,
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('prefers confirmed duration and falls back to item duration', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpExpandedPlayer(tester, harness);

      final item = testPlayerItem(
        title: 'Duration test',
        artist: 'Author',
        duration: const Duration(minutes: 10),
      );
      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.loading,
          duration: const Duration(minutes: 9, seconds: 42),
        ),
      );
      expect(find.text('9m 42s'), findsOneWidget);
      expect(find.text('10m 0s'), findsNothing);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.loading,
          duration: Duration.zero,
        ),
      );
      expect(find.text('9m 42s'), findsNothing);
      expect(find.text('10m 0s'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  for (final processingState in [
    PlaybackProcessingState.buffering,
    PlaybackProcessingState.completed,
    PlaybackProcessingState.error,
  ]) {
    testWidgets('keeps metadata and layout in ${processingState.name} state', (
      tester,
    ) async {
      final harness = PlayerWidgetHarness();
      try {
        await _pumpExpandedPlayer(tester, harness);

        await _emitSnapshot(
          tester,
          harness,
          buildPlaybackSnapshot(
            currentItem: testPlayerItem(
              title: 'Stateful episode',
              artist: 'Stateful author',
            ),
            processingState: processingState,
            playing: processingState == PlaybackProcessingState.buffering,
            position: processingState == PlaybackProcessingState.completed
                ? const Duration(minutes: 2)
                : Duration.zero,
            duration: const Duration(minutes: 2),
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

        expect(find.text('Stateful episode'), findsOneWidget);
        expect(find.text('Stateful author'), findsOneWidget);

        if (processingState == PlaybackProcessingState.buffering) {
          expect(find.byType(PlayerControlDock), findsOneWidget);
          expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
          expect(
            find.byKey(const ValueKey('expanded-player-buffering-spinner')),
            findsOneWidget,
          );
        } else if (processingState == PlaybackProcessingState.completed) {
          expect(find.byType(PlayerControlDock), findsOneWidget);
          expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
          expect(find.bySemanticsLabel('Phát lại'), findsOneWidget);
        } else {
          expect(find.byType(PlayerControlDock), findsNothing);
          expect(find.text('Network unavailable.'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('expanded-player-retry')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('expanded-player-retry')));
          expect(harness.gateway.callCountFor('retry'), 1);
          expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
        }
      } finally {
        await harness.dispose(tester);
      }
    });
  }

  testWidgets('shows non-recoverable error without retry action', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpExpandedPlayer(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(title: 'Fatal episode'),
          processingState: PlaybackProcessingState.error,
          failure: const PlayerFailure(
            code: 'unsupported',
            message: 'This content cannot be played.',
            isRecoverable: false,
            itemId: 'track-1',
          ),
        ),
      );

      expect(find.text('This content cannot be played.'), findsOneWidget);
      expect(find.byKey(const ValueKey('expanded-player-retry')), findsNothing);
      expect(find.byType(PlayerControlDock), findsNothing);
      expect(harness.gateway.callCountFor('retry'), 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('is safe while the current item is cleared', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpExpandedPlayer(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(title: 'Before stop'),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      expect(find.text('Before stop'), findsOneWidget);

      await _emitSnapshot(tester, harness, PlaybackSnapshot.idle);

      expect(find.byType(ExpandedPlayerScreen), findsOneWidget);
      expect(find.byType(PlayerArtworkHero), findsOneWidget);
      expect(find.text('Before stop'), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });
}

Future<void> _pumpExpandedPlayer(
  WidgetTester tester,
  PlayerWidgetHarness harness,
) async {
  await tester.pumpWidget(
    harness.wrap(const MaterialApp(home: ExpandedPlayerScreen())),
  );
  await tester.pump();
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
