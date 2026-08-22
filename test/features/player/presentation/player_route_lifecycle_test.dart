// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/application/player_cubit.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/expanded_player_screen.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_host.dart';
import '../support/fake_playback_gateway.dart';
import '../support/playback_snapshot_builder.dart';
import '../support/player_test_data.dart';
import '../support/player_widget_harness.dart';

void main() {
  testWidgets('push and close are playback-neutral', (tester) async {
    final harness = PlayerWidgetHarness();
    final observer = _RecordingNavigatorObserver();
    try {
      await _pumpHost(tester, harness, observer: observer);
      await _emitSnapshot(tester, harness, _activeSnapshot());
      final commandCountsBefore = _playbackCommandCounts(harness.gateway);

      await _openExpandedPlayer(tester);
      await tester.tap(find.byTooltip('Đóng về mini player').first);
      await tester.pumpAndSettle();

      expect(find.byType(ExpandedPlayerScreen), findsNothing);
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
      _expectPlaybackCommandsUnchanged(harness.gateway, commandCountsBefore);
      expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
      expect(
        observer.poppedRoutes.whereType<ExpandedPlayerRoute>(),
        hasLength(1),
      );
      expect(_playerCubitFrom(tester), same(harness.targetCubit));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('system back is playback-neutral', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpHost(tester, harness);
      await _emitSnapshot(tester, harness, _activeSnapshot());
      final commandCountsBefore = _playbackCommandCounts(harness.gateway);

      await _openExpandedPlayer(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ExpandedPlayerScreen), findsNothing);
      _expectPlaybackCommandsUnchanged(harness.gateway, commandCountsBefore);
      expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('swipe down is playback-neutral', (tester) async {
    final harness = PlayerWidgetHarness();
    try {
      await _pumpHost(tester, harness);
      await _emitSnapshot(tester, harness, _activeSnapshot());
      final commandCountsBefore = _playbackCommandCounts(harness.gateway);

      await _openExpandedPlayer(tester);
      await tester.drag(
        find.byKey(const ValueKey('expanded-player-dismiss-region')),
        const Offset(0, 420),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpandedPlayerScreen), findsNothing);
      expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
      _expectPlaybackCommandsUnchanged(harness.gateway, commandCountsBefore);
      expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets(
    'mini player continues from the same playback snapshot after pop',
    (tester) async {
      final harness = PlayerWidgetHarness();
      try {
        await _pumpHost(tester, harness);
        final initial = _activeSnapshot();
        await _emitSnapshot(tester, harness, initial);
        await _openExpandedPlayer(tester);

        Navigator.of(tester.element(find.byType(ExpandedPlayerScreen))).pop();
        await tester.pumpAndSettle();

        final updated = _activeSnapshot(position: const Duration(seconds: 15));
        await _emitSnapshot(tester, harness, updated);

        expect(harness.targetCubit.state.playback, same(updated));
        expect(find.byKey(const ValueKey('mini-player')), findsOneWidget);
        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(progress.value, closeTo(.25, .001));
        expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
      } finally {
        await harness.dispose(tester);
      }
    },
  );

  testWidgets('idle snapshot pops the top-most expanded route exactly once', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    final observer = _RecordingNavigatorObserver();
    try {
      await _pumpHost(tester, harness, observer: observer);
      await _emitSnapshot(tester, harness, _activeSnapshot());
      await _openExpandedPlayer(tester);
      final commandCountsBefore = _playbackCommandCounts(harness.gateway);

      await _emitSnapshot(tester, harness, PlaybackSnapshot.idle);
      await tester.pumpAndSettle();
      await _emitSnapshot(tester, harness, PlaybackSnapshot.idle);

      expect(find.byType(ExpandedPlayerScreen), findsNothing);
      expect(find.byKey(const ValueKey('mini-player')), findsNothing);
      expect(harness.targetCubit.state.playback, same(PlaybackSnapshot.idle));
      expect(
        observer.poppedRoutes.whereType<ExpandedPlayerRoute>(),
        hasLength(1),
      );
      _expectPlaybackCommandsUnchanged(harness.gateway, commandCountsBefore);
      expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('idle snapshot does not pop another top-most route', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    final observer = _RecordingNavigatorObserver();
    try {
      await _pumpHost(tester, harness, observer: observer);
      await _emitSnapshot(tester, harness, _activeSnapshot());
      await _openExpandedPlayer(tester);
      final commandCountsBefore = _playbackCommandCounts(harness.gateway);

      unawaited(
        Navigator.of(
          tester.element(find.byType(ExpandedPlayerScreen)),
        ).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other route')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _emitSnapshot(tester, harness, PlaybackSnapshot.idle);

      expect(find.text('Other route'), findsOneWidget);
      expect(observer.poppedRoutes.whereType<ExpandedPlayerRoute>(), isEmpty);
      expect(
        observer.poppedRoutes.whereType<MaterialPageRoute<void>>(),
        isEmpty,
      );
      _expectPlaybackCommandsUnchanged(harness.gateway, commandCountsBefore);
      expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('initial idle state closes a newly mounted expanded route', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    final observer = _RecordingNavigatorObserver();
    try {
      await _pumpHost(tester, harness, observer: observer);
      final commandCountsBefore = _playbackCommandCounts(harness.gateway);

      unawaited(
        Navigator.of(
          tester.element(find.byType(PlayerHost)),
        ).push<void>(ExpandedPlayerRoute()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpandedPlayerScreen), findsNothing);
      expect(find.byKey(const ValueKey('mini-player')), findsNothing);
      expect(
        observer.poppedRoutes.whereType<ExpandedPlayerRoute>(),
        hasLength(1),
      );
      _expectPlaybackCommandsUnchanged(harness.gateway, commandCountsBefore);
      expect(harness.gateway.snapshotSubscriptionCancelCount, 0);
    } finally {
      await harness.dispose(tester);
    }
  });
}

PlaybackSnapshot _activeSnapshot({Duration position = Duration.zero}) {
  final item = testPlayerItem(
    title: 'Route episode',
    artist: 'Route artist',
    duration: const Duration(minutes: 1),
  );
  return buildPlaybackSnapshot(
    currentItem: item,
    processingState: PlaybackProcessingState.ready,
    playing: true,
    position: position,
    duration: const Duration(minutes: 1),
  );
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

Future<void> _openExpandedPlayer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mini-player')));
  await tester.pumpAndSettle();
  expect(find.byType(ExpandedPlayerScreen), findsOneWidget);
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

({int pause, int play, int stop}) _playbackCommandCounts(
  FakePlaybackGateway gateway,
) => (
  pause: gateway.callCountFor('pause'),
  play: gateway.callCountFor('play'),
  stop: gateway.callCountFor('stop'),
);

void _expectPlaybackCommandsUnchanged(
  FakePlaybackGateway gateway,
  ({int pause, int play, int stop}) before,
) {
  expect(_playbackCommandCounts(gateway), before);
}

PlayerCubit _playerCubitFrom(WidgetTester tester) =>
    tester.element(find.byType(PlayerHost)).read<PlayerCubit>();

final class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> poppedRoutes = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRoutes.add(route);
    super.didPop(route, previousRoute);
  }
}
