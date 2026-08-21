// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_control_dock.dart';
import '../../support/playback_snapshot_builder.dart';
import '../../support/player_test_data.dart';
import '../../support/player_widget_harness.dart';

void main() {
  testWidgets('renders confirmed position, duration, and buffered progress', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
          position: const Duration(minutes: 4),
          bufferedPosition: const Duration(minutes: 6),
          duration: const Duration(minutes: 10),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 0.4);
      expect(slider.secondaryTrackValue, 0.6);
      expect(slider.onChanged, isNotNull);
      expect(find.text('4:00'), findsOneWidget);
      expect(find.text('-6:00'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('slider previews a position without seeking on change', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
          duration: const Duration(minutes: 10),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.0);
      slider.onChanged!(0.25);
      await tester.pump();

      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.25);
      expect(harness.gateway.callCountFor('seek'), 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('clamps buffered progress above duration', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
          bufferedPosition: const Duration(minutes: 15),
          duration: const Duration(minutes: 10),
        ),
      );

      expect(
        tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue,
        1.0,
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  for (final duration in [Duration.zero, const Duration(seconds: -1)]) {
    testWidgets('disables timeline controls for duration $duration', (
      tester,
    ) async {
      final harness = PlayerWidgetHarness();
      try {
        await _pumpDock(tester, harness);

        await _emitSnapshot(
          tester,
          harness,
          buildPlaybackSnapshot(
            currentItem: testPlayerItem(),
            processingState: PlaybackProcessingState.ready,
            duration: duration,
          ),
        );

        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
        expect(
          tester.widget<Slider>(find.byType(Slider)).secondaryTrackValue,
          isNull,
        );
        expect(_control('Tua lại 10 giây'), findsOneWidget);
        expect(_control('Tua tới 10 giây'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.descendant(
                  of: _control('Tua lại 10 giây'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(
                find.descendant(
                  of: _control('Tua tới 10 giây'),
                  matching: find.byType(IconButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(harness.gateway.callCountFor('skipBy'), 0);
      } finally {
        await harness.dispose(tester);
      }
    });
  }

  testWidgets('playback and skip controls delegate target commands', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.ready,
          playing: true,
          duration: const Duration(minutes: 10),
        ),
      );

      await tester.tap(_control('Tua lại 10 giây'));
      await tester.tap(_control('Tua tới 10 giây'));
      await tester.tap(find.bySemanticsLabel('Tạm dừng'));

      expect(harness.gateway.commands.map((command) => command.name), [
        'skipBy',
        'skipBy',
        'pause',
      ]);
      expect(harness.gateway.commands[0].arguments, {
        'offset': const Duration(seconds: -10),
      });
      expect(harness.gateway.commands[1].arguments, {
        'offset': const Duration(seconds: 10),
      });
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('completed state renders Replay and delegates play', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(),
          processingState: PlaybackProcessingState.completed,
          position: const Duration(minutes: 10),
          bufferedPosition: const Duration(minutes: 10),
          duration: const Duration(minutes: 10),
        ),
      );

      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Phát lại'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Phát lại'));

      expect(harness.gateway.callCountFor('play'), 1);
      expect(harness.gateway.callCountFor('pause'), 0);
      expect(harness.gateway.callCountFor('seek'), 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('main action stays unchanged until confirmed snapshot', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final paused = buildPlaybackSnapshot(
        currentItem: testPlayerItem(),
        processingState: PlaybackProcessingState.ready,
        duration: const Duration(minutes: 10),
      );
      await _emitSnapshot(tester, harness, paused);

      await tester.tap(find.bySemanticsLabel('Phát'));
      await tester.pump();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Phát'), findsOneWidget);
      expect(harness.gateway.callCountFor('play'), 1);

      await _emitSnapshot(tester, harness, paused.copyWith(playing: true));

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Tạm dừng'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });
}

Finder _control(String label) => find.bySemanticsLabel(label);

Future<void> _pumpDock(WidgetTester tester, PlayerWidgetHarness harness) async {
  await tester.pumpWidget(
    harness.wrap(const MaterialApp(home: Scaffold(body: PlayerControlDock()))),
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
