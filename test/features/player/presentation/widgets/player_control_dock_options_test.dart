// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/player_command_policies.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/domain/player_failure.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';
import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_control_dock.dart';
import '../../support/playback_snapshot_builder.dart';
import '../../support/player_test_data.dart';
import '../../support/player_widget_harness.dart';

void main() {
  testWidgets('delegates queue and option controls exactly once', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final first = testPlayerItem(id: 'first');
      final middle = testPlayerItem(id: 'middle');
      final last = testPlayerItem(id: 'last');
      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: middle,
          queue: [first, middle, last],
          currentIndex: 1,
        ),
      );

      await tester.tap(_control('Bài trước'));
      await tester.tap(_control('Bài tiếp theo'));
      await tester.tap(_control('Tốc độ phát 1.0x'));
      await tester.tap(_control('Lặp lại: tắt'));
      await tester.tap(_control('Trộn bài: tắt'));

      expect(harness.gateway.commands.map((command) => command.name), [
        'previous',
        'next',
        'setSpeed',
        'setRepeatMode',
        'setShuffleEnabled',
      ]);
      expect(harness.gateway.callCountFor('previous'), 1);
      expect(harness.gateway.callCountFor('next'), 1);
      expect(harness.gateway.callCountFor('setSpeed'), 1);
      expect(harness.gateway.callCountFor('setRepeatMode'), 1);
      expect(harness.gateway.callCountFor('setShuffleEnabled'), 1);
      expect(harness.gateway.commands[2].arguments, {'speed': 1.25});
      expect(harness.gateway.commands[3].arguments, {
        'mode': PlayerRepeatMode.one,
      });
      expect(harness.gateway.commands[4].arguments, {'enabled': true});
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('renders option state only after confirmed snapshots', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final item = testPlayerItem();
      final confirmedOff = _activeSnapshot(
        currentItem: item,
        queue: [item],
        currentIndex: 0,
      );
      await _emitSnapshot(tester, harness, confirmedOff);

      expect(
        _icon(tester, 'Lặp lại: tắt', Icons.repeat_rounded).color,
        const Color(0xff94a3b8),
      );
      expect(
        _icon(tester, 'Trộn bài: tắt', Icons.shuffle_rounded).color,
        const Color(0xff94a3b8),
      );

      await tester.tap(_control('Tốc độ phát 1.0x'));
      await tester.tap(_control('Lặp lại: tắt'));
      await tester.tap(_control('Trộn bài: tắt'));

      expect(find.text('1.0x'), findsOneWidget);
      expect(_control('Lặp lại: tắt'), findsOneWidget);
      expect(_control('Trộn bài: tắt'), findsOneWidget);

      await _emitSnapshot(
        tester,
        harness,
        confirmedOff.copyWith(
          speed: 1.25,
          repeatMode: PlayerRepeatMode.one,
          shuffleEnabled: true,
        ),
      );

      expect(find.text('1.25x'), findsOneWidget);
      expect(_control('Lặp lại: một'), findsOneWidget);
      expect(_control('Trộn bài: bật'), findsOneWidget);
      expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(
        _icon(tester, 'Lặp lại: một', Icons.repeat_one_rounded).color,
        const Color(0xfff2542c),
      );
      expect(
        _icon(tester, 'Trộn bài: bật', Icons.shuffle_rounded).color,
        const Color(0xfff2542c),
      );

      await _emitSnapshot(
        tester,
        harness,
        confirmedOff.copyWith(repeatMode: PlayerRepeatMode.all),
      );
      expect(_control('Lặp lại: tất cả'), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
      expect(
        _icon(tester, 'Lặp lại: tất cả', Icons.repeat_rounded).color,
        const Color(0xfff2542c),
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('uses the next preset above a confirmed non-preset speed', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final item = testPlayerItem();
      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: item,
          queue: [item],
          currentIndex: 0,
          speed: 1.1,
        ),
      );

      await tester.tap(_control('Tốc độ phát 1.1x'));

      expect(harness.gateway.callCountFor('setSpeed'), 1);
      expect(harness.gateway.commands.single.arguments, {'speed': 1.25});
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('follows confirmed queue boundaries', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final items = [
        testPlayerItem(id: 'first'),
        testPlayerItem(id: 'middle'),
        testPlayerItem(id: 'last'),
      ];

      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: items.first,
          queue: items,
          currentIndex: 0,
        ),
      );
      expect(_button(tester, 'Bài trước').onPressed, isNull);
      expect(_button(tester, 'Bài tiếp theo').onPressed, isNotNull);

      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(currentItem: items[1], queue: items, currentIndex: 1),
      );
      expect(_button(tester, 'Bài trước').onPressed, isNotNull);
      expect(_button(tester, 'Bài tiếp theo').onPressed, isNotNull);

      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(currentItem: items.last, queue: items, currentIndex: 2),
      );
      expect(_button(tester, 'Bài trước').onPressed, isNotNull);
      expect(_button(tester, 'Bài tiếp theo').onPressed, isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('allows navigation at repeat-all boundaries', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final first = testPlayerItem(id: 'first');
      final last = testPlayerItem(id: 'last');
      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: first,
          queue: [first, last],
          currentIndex: 0,
          repeatMode: PlayerRepeatMode.all,
        ),
      );
      expect(_button(tester, 'Bài trước').onPressed, isNotNull);

      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: last,
          queue: [first, last],
          currentIndex: 1,
          repeatMode: PlayerRepeatMode.all,
        ),
      );
      expect(_button(tester, 'Bài tiếp theo').onPressed, isNotNull);

      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: first,
          queue: [first],
          currentIndex: 0,
          repeatMode: PlayerRepeatMode.all,
        ),
      );
      expect(_button(tester, 'Bài trước').onPressed, isNull);
      expect(_button(tester, 'Bài tiếp theo').onPressed, isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('enables previous at the first item only after three seconds', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final first = testPlayerItem(id: 'first');
      final last = testPlayerItem(id: 'last');
      final queue = [first, last];

      for (final position in [
        PlayerCommandPolicies.previousRestartThreshold -
            const Duration(microseconds: 1),
        PlayerCommandPolicies.previousRestartThreshold,
        PlayerCommandPolicies.previousRestartThreshold +
            const Duration(microseconds: 1),
      ]) {
        await _emitSnapshot(
          tester,
          harness,
          _activeSnapshot(
            currentItem: first,
            queue: queue,
            currentIndex: 0,
            position: position,
          ),
        );

        expect(
          _button(tester, 'Bài trước').onPressed,
          position > PlayerCommandPolicies.previousRestartThreshold
              ? isNotNull
              : isNull,
        );
      }
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('disables queue and options during initial loading', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(processingState: PlaybackProcessingState.loading),
      );

      for (final label in [
        'Bài trước',
        'Bài tiếp theo',
        'Tốc độ phát 1.0x',
        'Lặp lại: tắt',
        'Trộn bài: tắt',
      ]) {
        expect(_button(tester, label).onPressed, isNull);
      }
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('keeps active queue controls during replacement loading', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final first = testPlayerItem(id: 'first');
      final middle = testPlayerItem(id: 'middle');
      final last = testPlayerItem(id: 'last');
      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: middle,
          queue: [first, middle, last],
          currentIndex: 1,
          processingState: PlaybackProcessingState.loading,
        ),
      );

      for (final label in [
        'Bài trước',
        'Bài tiếp theo',
        'Tốc độ phát 1.0x',
        'Lặp lại: tắt',
        'Trộn bài: tắt',
      ]) {
        expect(_button(tester, label).onPressed, isNotNull);
      }
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('disables queue and options for active error snapshots', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpDock(tester, harness);

      final item = testPlayerItem();
      await _emitSnapshot(
        tester,
        harness,
        _activeSnapshot(
          currentItem: item,
          queue: [
            item,
            testPlayerItem(id: 'next'),
          ],
          currentIndex: 0,
          processingState: PlaybackProcessingState.error,
          failure: const PlayerFailure(
            code: 'network',
            message: 'Network unavailable.',
            isRecoverable: true,
          ),
        ),
      );

      for (final label in [
        'Bài trước',
        'Bài tiếp theo',
        'Tốc độ phát 1.0x',
        'Lặp lại: tắt',
        'Trộn bài: tắt',
      ]) {
        expect(_button(tester, label).onPressed, isNull);
      }
    } finally {
      await harness.dispose(tester);
    }
  });
}

Finder _control(String label) => find.bySemanticsLabel(label);

IconButton _button(WidgetTester tester, String label) => tester.widget(
  find.descendant(of: _control(label), matching: find.byType(IconButton)),
);

Icon _icon(WidgetTester tester, String label, IconData icon) => tester.widget(
  find.descendant(of: _control(label), matching: find.byIcon(icon)),
);

PlaybackSnapshot _activeSnapshot({
  required PlayerItem currentItem,
  required List<PlayerItem> queue,
  required int currentIndex,
  PlaybackProcessingState processingState = PlaybackProcessingState.ready,
  Duration position = Duration.zero,
  double speed = 1.0,
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off,
  bool shuffleEnabled = false,
  PlayerFailure? failure,
}) => buildPlaybackSnapshot(
  currentItem: currentItem,
  queue: queue,
  currentIndex: currentIndex,
  processingState: processingState,
  position: position,
  duration: const Duration(minutes: 10),
  speed: speed,
  repeatMode: repeatMode,
  shuffleEnabled: shuffleEnabled,
  failure: failure,
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
