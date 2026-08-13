// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import 'package:vi_listen/features/player/infrastructure/interruption_observer.dart';

import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late StreamController<AudioInterruptionEvent> interruptions;
  late StreamController<void> becomingNoisy;
  late StreamController<PlaybackSnapshot> snapshots;

  setUp(() {
    interruptions = StreamController<AudioInterruptionEvent>.broadcast(sync: true);
    becomingNoisy = StreamController<void>.broadcast(sync: true);
    snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  });

  tearDown(() async {
    await interruptions.close();
    await becomingNoisy.close();
    await snapshots.close();
  });

  test('becoming-noisy observer issues zero application engine commands', () async {
    final engine = FakePlaybackEngine();

    final observer = InterruptionObserver(
      interruptionEvents: interruptions.stream,
      becomingNoisyEvents: becomingNoisy.stream,
      confirmedSnapshots: snapshots.stream,
    );

    addTearDown(() async {
      await observer.dispose();
      await engine.dispose();
    });

    final observations = <InterruptionObservation>[];
    final subscription = observer.observations.listen(observations.add);
    addTearDown(subscription.cancel);

    final playing = PlaybackSnapshot.idle.copyWith(processingState: PlaybackProcessingState.ready, playing: true);

    snapshots.add(playing);

    becomingNoisy.add(null);

    await pumpEventQueue();

    expect(observations, hasLength(1));
    expect(observations.single.kind, InterruptionObservationKind.becomingNoisy);
    expect(observations.single.latestConfirmedSnapshot, same(playing));

    // PLR-085: the app observer is passive.
    expect(engine.calls, isEmpty);
    expect(engine.callCountFor('pause'), 0);
    expect(engine.callCountFor('play'), 0);
  });

  test('one becoming-noisy event has one runtime-owner pause and no app resume', () async {
    final engine = FakePlaybackEngine();
    final handler = AppAudioHandler(engine, FakePlayerClock());

    final observer = InterruptionObserver(
      interruptionEvents: interruptions.stream,
      becomingNoisyEvents: becomingNoisy.stream,
      confirmedSnapshots: handler.snapshots,
    );

    addTearDown(() async {
      await observer.dispose();
      await handler.dispose();
    });

    final observations = <InterruptionObservation>[];
    final subscription = observer.observations.listen(observations.add);
    addTearDown(subscription.cancel);

    final item = testPlayerItem(id: 'becoming-noisy-owner');

    final load = handler.handleLoadQueue([item], 0, false, _testSource);

    await pumpEventQueue();

    engine.loadRequests.single.complete();
    await load;

    // Establish engine-confirmed playing state.
    engine.emitPlayerState(just_audio.PlayerState(true, just_audio.ProcessingState.ready));

    await pumpEventQueue();

    expect(handler.playbackState.value.playing, isTrue);

    // The AudioSession event reaches the app observer.
    becomingNoisy.add(null);

    // The observer itself must not issue Pause.
    expect(engine.callCountFor('pause'), 0);
    expect(engine.callCountFor('play'), 0);

    // Simulate the single Pause owned by just_audio.
    await engine.pause();

    engine.emitPlayerState(just_audio.PlayerState(false, just_audio.ProcessingState.ready));

    await pumpEventQueue();

    // Exactly one runtime-owner Pause. No second competing Pause.
    expect(engine.callCountFor('pause'), 1);
    expect(handler.playbackState.value.playing, isFalse);

    expect(observations, hasLength(1));
    expect(observations.single.kind, InterruptionObservationKind.becomingNoisy);

    // A physical route becoming available again has no application
    // resume command path. Real route restoration is verified on-device.
    await pumpEventQueue();

    expect(engine.callCountFor('pause'), 1);
    expect(engine.callCountFor('play'), 0);
    expect(handler.playbackState.value.playing, isFalse);
  });
}

const _testSource = CommandSource.ui;
