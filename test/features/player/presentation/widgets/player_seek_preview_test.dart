// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_control_dock.dart';
import '../../support/playback_snapshot_builder.dart';
import '../../support/player_test_data.dart';
import '../../support/player_widget_harness.dart';

void main() {
  testWidgets('multiple pointer updates only update local preview', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(
        tester,
        harness,
        _snapshot(position: const Duration(minutes: 1)),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.1);
      slider.onChanged!(0.25);
      slider.onChanged!(0.75);
      await tester.pump();

      final previewSlider = tester.widget<Slider>(find.byType(Slider));
      expect(previewSlider.value, 0.75);
      expect(find.text('7:30'), findsOneWidget);
      expect(find.text('-2:30'), findsOneWidget);
      expect(harness.gateway.callCountFor('seek'), 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('drag end commits exactly once with the final value', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(tester, harness, _snapshot());

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.1);
      slider.onChanged!(0.2);
      slider.onChangeEnd!(0.65);
      await tester.pump();

      expect(harness.gateway.callCountFor('seek'), 1);
      expect(harness.gateway.commands.single.arguments, {
        'position': const Duration(minutes: 6, seconds: 30),
      });
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('a real gesture sends no seek until pointer up', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(tester, harness, _snapshot());

      final sliderFinder = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(harness.gateway.callCountFor('seek'), 0);

      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(harness.gateway.callCountFor('seek'), 0);

      await gesture.up();
      await tester.pump();
      expect(harness.gateway.callCountFor('seek'), 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('position snapshots do not replace the preview during drag', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(
        tester,
        harness,
        _snapshot(position: const Duration(minutes: 2)),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.75);
      slider.onChanged!(0.75);
      await tester.pump();

      await _emitSnapshot(
        tester,
        harness,
        _snapshot(position: const Duration(minutes: 1)),
      );

      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.75);
      expect(find.text('7:30'), findsOneWidget);
      expect(find.text('-2:30'), findsOneWidget);
      expect(harness.gateway.callCountFor('seek'), 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('duration becoming zero cancels the active preview safely', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(tester, harness, _snapshot());

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.5);
      slider.onChanged!(0.5);
      final staleOnChangeEnd = slider.onChangeEnd!;
      await tester.pump();

      await _emitSnapshot(tester, harness, _snapshot(duration: Duration.zero));

      final unavailableSlider = tester.widget<Slider>(find.byType(Slider));
      expect(unavailableSlider.value, 0.0);
      expect(unavailableSlider.onChangeStart, isNull);
      expect(unavailableSlider.onChanged, isNull);
      expect(unavailableSlider.onChangeEnd, isNull);
      staleOnChangeEnd(0.5);
      await tester.pump();
      expect(harness.gateway.callCountFor('seek'), 0);

      await _emitSnapshot(
        tester,
        harness,
        _snapshot(position: const Duration(minutes: 1)),
      );
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('changing item during drag cancels the old item preview', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(
        tester,
        harness,
        _snapshot(item: testPlayerItem(id: 'track-a')),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.8);
      slider.onChanged!(0.8);
      final staleOnChangeEnd = slider.onChangeEnd!;
      await tester.pump();

      await _emitSnapshot(
        tester,
        harness,
        _snapshot(
          item: testPlayerItem(id: 'track-b'),
          position: const Duration(minutes: 2),
        ),
      );

      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.2);
      staleOnChangeEnd(0.8);
      await tester.pump();
      expect(harness.gateway.callCountFor('seek'), 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('confirmed engine snapshot replaces the committed preview', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);
      await _emitSnapshot(
        tester,
        harness,
        _snapshot(position: const Duration(minutes: 1)),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.8);
      slider.onChanged!(0.8);
      slider.onChangeEnd!(0.8);
      await tester.pump();

      expect(harness.gateway.callCountFor('seek'), 1);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.1);

      await _emitSnapshot(
        tester,
        harness,
        _snapshot(position: const Duration(minutes: 7, seconds: 15)),
      );

      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.725);
      expect(find.text('7:15'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });
}

PlaybackSnapshot _snapshot({
  PlayerItem? item,
  Duration position = Duration.zero,
  Duration duration = const Duration(minutes: 10),
}) => buildPlaybackSnapshot(
  currentItem: item ?? testPlayerItem(),
  processingState: PlaybackProcessingState.ready,
  position: position,
  duration: duration,
);

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
