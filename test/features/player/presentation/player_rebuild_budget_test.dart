// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/presentation/expanded_player_screen.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_artwork.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_control_dock.dart';
import 'package:vi_listen/features/player/presentation/widgets/mini_player.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';
import '../support/player_widget_harness.dart';

void main() {
  testWidgets('mini position ticks rebuild only progress', (tester) async {
    final harness = PlayerWidgetHarness();
    final tracker = _RebuildTracker()..attach();
    addTearDown(tracker.restore);
    try {
      await tester.pumpWidget(
        harness.wrap(
          const MaterialApp(
            home: Scaffold(body: MiniPlayer(onOpen: _noop)),
          ),
        ),
      );
      await tester.pump();

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
          playing: true,
          duration: const Duration(minutes: 10),
        ),
      );

      final metadataSelector = _nearestBlocSelector(
        tester,
        find.text('Episode A'),
      );
      final artworkSelector = _nearestBlocSelector(
        tester,
        find.byType(PlayerArtwork),
      );
      final progressSelector = _nearestBlocSelector(
        tester,
        find.byType(LinearProgressIndicator),
      );
      final playbackSelector = _nearestBlocSelector(
        tester,
        find.byIcon(Icons.pause_rounded),
      );
      tracker.reset();

      for (var tick = 1; tick <= 4; tick++) {
        await _emitSnapshot(
          tester,
          harness,
          buildPlaybackSnapshot(
            currentItem: item,
            processingState: PlaybackProcessingState.ready,
            playing: true,
            position: Duration(milliseconds: tick * 200),
            duration: const Duration(minutes: 10),
          ),
        );
      }

      expect(tracker.count(metadataSelector), 0);
      expect(tracker.count(artworkSelector), 0);
      expect(tracker.count(playbackSelector), 0);
      expect(tracker.count(progressSelector), greaterThan(0));
      expect(harness.gateway.commands, isEmpty);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('dock position ticks stop before-navigation at its threshold', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    final tracker = _RebuildTracker()..attach();
    addTearDown(tracker.restore);
    try {
      await _pumpDock(tester, harness);
      final first = testPlayerItem(id: 'first');
      final middle = testPlayerItem(id: 'middle');
      final last = testPlayerItem(id: 'last');
      final snapshot = buildPlaybackSnapshot(
        currentItem: first,
        queue: [first, middle, last],
        currentIndex: 0,
        processingState: PlaybackProcessingState.ready,
        duration: const Duration(minutes: 10),
      );
      await _emitSnapshot(tester, harness, snapshot);

      final timelineSelector = _nearestBlocSelector(
        tester,
        find.byType(Slider),
      );
      final previousSelector = _nearestBlocSelector(
        tester,
        _control('Bài trước'),
      );
      final nextSelector = _nearestBlocSelector(
        tester,
        _control('Bài tiếp theo'),
      );
      final playbackSelector = _nearestBlocSelector(
        tester,
        find.bySemanticsLabel('Phát'),
      );
      final speedSelector = _nearestBlocSelector(
        tester,
        _control('Tốc độ phát 1.0x'),
      );
      final repeatSelector = _nearestBlocSelector(
        tester,
        _control('Lặp lại: tắt'),
      );
      final shuffleSelector = _nearestBlocSelector(
        tester,
        _control('Trộn bài: tắt'),
      );
      tracker.reset();

      for (var tick = 1; tick <= 14; tick++) {
        await _emitSnapshot(
          tester,
          harness,
          snapshot.copyWith(position: Duration(milliseconds: tick * 200)),
        );
      }

      expect(tracker.count(timelineSelector), greaterThan(0));
      expect(tracker.count(previousSelector), 0);
      expect(tracker.count(nextSelector), 0);
      expect(tracker.count(playbackSelector), 0);
      expect(tracker.count(speedSelector), 0);
      expect(tracker.count(repeatSelector), 0);
      expect(tracker.count(shuffleSelector), 0);

      final previousBeforeThreshold = tracker.count(previousSelector);
      await _emitSnapshot(
        tester,
        harness,
        snapshot.copyWith(position: const Duration(milliseconds: 3200)),
      );
      expect(tracker.count(previousSelector), previousBeforeThreshold + 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('seek drag dirties only the timeline subtree', (tester) async {
    final harness = PlayerWidgetHarness();
    final tracker = _RebuildTracker()..attach();
    addTearDown(tracker.restore);
    try {
      await _pumpDock(tester, harness);
      final item = testPlayerItem();
      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: item,
          currentIndex: 0,
          queue: [item],
          processingState: PlaybackProcessingState.ready,
          duration: const Duration(minutes: 10),
        ),
      );

      final timelineView = _ancestorWithRuntimeType(
        tester,
        find.byType(Slider),
        '_DockTimelineView',
      );
      final playbackSelector = _nearestBlocSelector(
        tester,
        find.bySemanticsLabel('Phát'),
      );
      final speedSelector = _nearestBlocSelector(
        tester,
        _control('Tốc độ phát 1.0x'),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      tracker.reset();

      slider.onChangeStart!(0);
      for (final value in [0.15, 0.35, 0.65, 0.85]) {
        tester.widget<Slider>(find.byType(Slider)).onChanged!(value);
        await tester.pump();
      }

      expect(tracker.count(timelineView), greaterThan(0));
      expect(tracker.count(playbackSelector), 0);
      expect(tracker.count(speedSelector), 0);
      expect(harness.gateway.callCountFor('seek'), 0);

      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0.85);
      expect(harness.gateway.callCountFor('seek'), 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('options rebuild only the option that changed', (tester) async {
    final harness = PlayerWidgetHarness();
    final tracker = _RebuildTracker()..attach();
    addTearDown(tracker.restore);
    try {
      await _pumpDock(tester, harness);
      final item = testPlayerItem();
      final snapshot = buildPlaybackSnapshot(
        currentItem: item,
        currentIndex: 0,
        queue: [item],
        processingState: PlaybackProcessingState.ready,
        duration: const Duration(minutes: 10),
      );
      await _emitSnapshot(tester, harness, snapshot);

      final speedSelector = _nearestBlocSelector(
        tester,
        _control('Tốc độ phát 1.0x'),
      );
      final repeatSelector = _nearestBlocSelector(
        tester,
        _control('Lặp lại: tắt'),
      );
      final shuffleSelector = _nearestBlocSelector(
        tester,
        _control('Trộn bài: tắt'),
      );

      tracker.reset();
      await _emitSnapshot(tester, harness, snapshot.copyWith(speed: 1.25));
      expect(tracker.count(speedSelector), greaterThan(0));
      expect(tracker.count(repeatSelector), 0);
      expect(tracker.count(shuffleSelector), 0);

      tracker.reset();
      await _emitSnapshot(
        tester,
        harness,
        snapshot.copyWith(repeatMode: PlayerRepeatMode.one, speed: 1.25),
      );
      expect(tracker.count(speedSelector), 0);
      expect(tracker.count(repeatSelector), greaterThan(0));
      expect(tracker.count(shuffleSelector), 0);

      tracker.reset();
      await _emitSnapshot(
        tester,
        harness,
        snapshot.copyWith(
          repeatMode: PlayerRepeatMode.one,
          speed: 1.25,
          shuffleEnabled: true,
        ),
      );
      expect(tracker.count(speedSelector), 0);
      expect(tracker.count(repeatSelector), 0);
      expect(tracker.count(shuffleSelector), greaterThan(0));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('expanded position ticks leave metadata and transcript still', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    final tracker = _RebuildTracker()..attach();
    addTearDown(tracker.restore);
    try {
      await tester.pumpWidget(
        harness.wrap(const MaterialApp(home: ExpandedPlayerScreen())),
      );
      await tester.pump();

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
          currentIndex: 0,
          queue: [item],
          processingState: PlaybackProcessingState.ready,
          duration: const Duration(minutes: 10),
        ),
      );

      final expandedElement = tester.element(find.byType(ExpandedPlayerScreen));
      final metadataSelector = _nearestBlocSelector(
        tester,
        find.text('Episode A'),
      );
      final artworkSelector = _nearestBlocSelector(
        tester,
        find.byType(PlayerArtwork),
      );
      final timelineSelector = _nearestBlocSelector(
        tester,
        find.byType(Slider),
      );
      final transcriptText = tester.element(
        find.text(
          "Welcome to The English We Speak, I'm Feifei and joining me is Roy.",
        ),
      );
      tracker.reset();

      for (var tick = 1; tick <= 4; tick++) {
        await _emitSnapshot(
          tester,
          harness,
          buildPlaybackSnapshot(
            currentItem: item,
            currentIndex: 0,
            queue: [item],
            processingState: PlaybackProcessingState.ready,
            position: Duration(milliseconds: tick * 200),
            duration: const Duration(minutes: 10),
          ),
        );
      }

      expect(tracker.count(expandedElement), 0);
      expect(tracker.count(metadataSelector), 0);
      expect(tracker.count(artworkSelector), 0);
      expect(tracker.count(transcriptText), 0);
      expect(tracker.count(timelineSelector), greaterThan(0));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('metadata updates do not create playback commands', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await tester.pumpWidget(
        harness.wrap(
          const MaterialApp(
            home: Scaffold(body: MiniPlayer(onOpen: _noop)),
          ),
        ),
      );
      await tester.pump();

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(title: 'Episode A'),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(title: 'Episode B'),
          processingState: PlaybackProcessingState.ready,
        ),
      );

      expect(find.text('Episode B'), findsOneWidget);
      expect(harness.gateway.commands, isEmpty);
    } finally {
      await harness.dispose(tester);
    }
  });
}

class _RebuildTracker {
  final Map<Element, int> _counts = <Element, int>{};
  RebuildDirtyWidgetCallback? _previous;

  void attach() {
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      _counts.update(element, (count) => count + 1, ifAbsent: () => 1);
      _previous?.call(element, builtOnce);
    };
  }

  int count(Element element) => _counts[element] ?? 0;

  void reset() => _counts.clear();

  void restore() {
    debugOnRebuildDirtyWidget = _previous;
    _previous = null;
  }
}

Element _nearestBlocSelector(WidgetTester tester, Finder finder) {
  final leaf = tester.element(finder);
  Element? selector;
  leaf.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType.toString().startsWith('BlocSelector')) {
      selector = ancestor;
      return false;
    }
    return true;
  });

  if (selector == null) {
    throw StateError('No BlocSelector ancestor for $finder');
  }
  return selector!;
}

Element _ancestorWithRuntimeType(
  WidgetTester tester,
  Finder finder,
  String runtimeType,
) {
  final leaf = tester.element(finder);
  Element? match;
  leaf.visitAncestorElements((ancestor) {
    if (ancestor.widget.runtimeType.toString() == runtimeType) {
      match = ancestor;
      return false;
    }
    return true;
  });

  if (match == null) {
    throw StateError('No $runtimeType ancestor for $finder');
  }
  return match!;
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

void _noop() {}
