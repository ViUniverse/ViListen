// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/widgets/mini_player.dart';
import '../../support/playback_snapshot_builder.dart';
import '../../support/player_test_data.dart';
import '../../support/player_widget_harness.dart';

void main() {
  testWidgets('renders metadata and semantics from the current item', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpMiniPlayer(tester, harness);

      final item = testPlayerItem(
        title: 'A different episode',
        artist: 'A different artist',
        duration: const Duration(seconds: 27),
      );
      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: item,
          processingState: PlaybackProcessingState.ready,
        ),
      );

      expect(find.text('A different episode'), findsOneWidget);
      expect(find.text('A different artist • 27s'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('mini-player')))
            .label,
        contains('Mở trình phát A different episode'),
      );
      expect(
        find.bySemanticsLabel(RegExp('Ảnh bìa A different episode')),
        findsOneWidget,
      );
      expect(find.text('BBC Learning English'), findsNothing);
      expect(find.text('The English We Speak: On their toes'), findsNothing);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('updates metadata when the current item changes', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpMiniPlayer(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(
            title: 'First episode',
            artist: 'First artist',
          ),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      expect(find.text('First episode'), findsOneWidget);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(
            id: 'track-2',
            title: 'Second episode',
            artist: 'Second artist',
            duration: const Duration(minutes: 1, seconds: 5),
          ),
          processingState: PlaybackProcessingState.ready,
        ),
      );

      expect(find.text('First episode'), findsNothing);
      expect(find.text('Second episode'), findsOneWidget);
      expect(find.text('Second artist • 1m 5s'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('shows pause intent and spinner while buffering', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpMiniPlayer(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.buffering,
          playing: true,
        ),
      );

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byTooltip('Tạm dừng'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('does not change the icon before a command snapshot', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpMiniPlayer(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
          playing: true,
        ),
      );

      await tester.tap(find.byTooltip('Tạm dừng'));
      await tester.pump();

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byTooltip('Tạm dừng'), findsOneWidget);
      expect(harness.gateway.callCountFor('pause'), 1);
    } finally {
      await harness.dispose(tester);
    }
  });
}

Future<void> _pumpMiniPlayer(
  WidgetTester tester,
  PlayerWidgetHarness harness,
) async {
  await tester.pumpWidget(
    harness.wrap(
      const MaterialApp(
        home: Scaffold(body: MiniPlayer(onOpen: _noop)),
      ),
    ),
  );
  await tester.pump();
}

void _noop() {}

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
