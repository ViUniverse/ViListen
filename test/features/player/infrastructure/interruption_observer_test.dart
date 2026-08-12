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
  late InterruptionObserver observer;

  setUp(() {
    interruptions = StreamController<AudioInterruptionEvent>.broadcast(
      sync: true,
    );
    becomingNoisy = StreamController<void>.broadcast(sync: true);
    snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
    observer = InterruptionObserver(
      interruptionEvents: interruptions.stream,
      becomingNoisyEvents: becomingNoisy.stream,
      confirmedSnapshots: snapshots.stream,
    );
  });

  tearDown(() async {
    await observer.dispose();
    await interruptions.close();
    await becomingNoisy.close();
    await snapshots.close();
  });

  test('normalizes begin, end, and becoming-noisy with latest snapshot', () {
    final events = <InterruptionObservation>[];
    final subscription = observer.observations.listen(events.add);
    addTearDown(subscription.cancel);
    final playing = PlaybackSnapshot.idle.copyWith(
      processingState: PlaybackProcessingState.ready,
      playing: true,
    );

    snapshots.add(playing);
    interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    interruptions.add(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    becomingNoisy.add(null);

    expect(events.map((event) => event.kind), [
      InterruptionObservationKind.begin,
      InterruptionObservationKind.end,
      InterruptionObservationKind.becomingNoisy,
    ]);
    expect(events[0].interruptionType, AudioInterruptionType.pause);
    expect(events[1].interruptionType, AudioInterruptionType.pause);
    expect(events[2].interruptionType, isNull);
    expect(
      events.map((event) => event.latestConfirmedSnapshot),
      everyElement(same(playing)),
    );
  });

  test(
    'observes confirmed snapshots without inferring interruption ordering',
    () {
      final events = <InterruptionObservation>[];
      final subscription = observer.observations.listen(events.add);
      addTearDown(subscription.cancel);
      final playing = PlaybackSnapshot.idle.copyWith(
        processingState: PlaybackProcessingState.ready,
        playing: true,
      );
      final paused = playing.copyWith(playing: false);

      snapshots.add(playing);
      interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      snapshots.add(paused);
      interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      expect(events[0].latestConfirmedSnapshot, same(playing));
      expect(events[1].latestConfirmedSnapshot, same(paused));
    },
  );

  test('observer events issue zero fake-engine commands', () async {
    final engine = FakePlaybackEngine();
    final engineSnapshotController = StreamController<PlaybackSnapshot>();
    final engineObserver = InterruptionObserver(
      interruptionEvents: interruptions.stream,
      becomingNoisyEvents: becomingNoisy.stream,
      confirmedSnapshots: engineSnapshotController.stream,
    );
    addTearDown(() async {
      await engineObserver.dispose();
      await engineSnapshotController.close();
      await engine.dispose();
    });

    interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    interruptions.add(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    becomingNoisy.add(null);

    expect(engine.calls, isEmpty);
  });

  test('forwards an input error without issuing a command', () async {
    final errors = <Object>[];
    final subscription = observer.observations.listen(
      (_) {},
      onError: errors.add,
    );
    addTearDown(subscription.cancel);
    final engine = FakePlaybackEngine();
    addTearDown(engine.dispose);

    interruptions.addError(StateError('session stream failed'));

    expect(errors.single, isA<StateError>());
    expect(engine.calls, isEmpty);
  });

  test(
    'runtime owner is sole pause/resume owner in handler integration',
    () async {
      final engine = FakePlaybackEngine();
      final handler = AppAudioHandler(engine, FakePlayerClock());
      final integrationObserver = InterruptionObserver(
        interruptionEvents: interruptions.stream,
        becomingNoisyEvents: becomingNoisy.stream,
        confirmedSnapshots: handler.snapshots,
      );
      addTearDown(() async {
        await integrationObserver.dispose();
        await handler.dispose();
      });
      final observations = <InterruptionObservation>[];
      final subscription = integrationObserver.observations.listen(
        observations.add,
      );
      addTearDown(subscription.cancel);
      final item = testPlayerItem(id: 'interruption-owner');

      final load = handler.handleLoadQueue([item], 0, false, _testSource);
      await pumpEventQueue();
      engine.loadRequests.single.complete();
      await load;
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(engine.callCountFor('pause'), 0);
      expect(handler.playbackState.value.playing, isTrue);

      // Simulates the one pause issued by the runtime owner, followed by its
      // engine confirmation. The observer must not add another command.
      await engine.pause();
      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      expect(engine.callCountFor('pause'), 1);
      expect(handler.playbackState.value.playing, isFalse);

      interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(engine.callCountFor('play'), 0);
      await engine.play();
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      expect(engine.callCountFor('play'), 1);
      expect(handler.playbackState.value.playing, isTrue);
      expect(observations, hasLength(2));
      expect(observations[0].latestConfirmedSnapshot.playing, isTrue);
      expect(observations[1].latestConfirmedSnapshot.playing, isFalse);
    },
  );

  test(
    'user pause during interruption does not make observer play on end',
    () async {
      final engine = FakePlaybackEngine();
      final handler = AppAudioHandler(engine, FakePlayerClock());
      final integrationObserver = InterruptionObserver(
        interruptionEvents: interruptions.stream,
        becomingNoisyEvents: becomingNoisy.stream,
        confirmedSnapshots: handler.snapshots,
      );
      addTearDown(() async {
        await integrationObserver.dispose();
        await handler.dispose();
      });
      final observations = <InterruptionObservation>[];
      final subscription = integrationObserver.observations.listen(
        observations.add,
      );
      addTearDown(subscription.cancel);
      final item = testPlayerItem(id: 'interruption-user-pause');

      final load = handler.handleLoadQueue([item], 0, false, _testSource);
      await pumpEventQueue();
      engine.loadRequests.single.complete();
      await load;
      engine.emitPlayerState(
        just_audio.PlayerState(true, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();

      interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      // The sole runtime owner pauses and the handler projects its confirmed
      // state. The user Pause below must not add a competing Pause command.
      await engine.pause();
      engine.emitPlayerState(
        just_audio.PlayerState(false, just_audio.ProcessingState.ready),
      );
      await pumpEventQueue();
      expect(engine.callCountFor('pause'), 1);
      expect(handler.playbackState.value.playing, isFalse);

      await handler.handlePause(_testSource);
      expect(engine.callCountFor('pause'), 1);
      interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );

      // The runtime owner chooses to remain paused. This proves observer
      // passivity only; it does not claim to override just_audio's private
      // conditional-resume state.
      expect(engine.callCountFor('play'), 0);
      expect(handler.playbackState.value.playing, isFalse);
      expect(observations.map((event) => event.kind), [
        InterruptionObservationKind.begin,
        InterruptionObservationKind.end,
      ]);
    },
  );

  test(
    'owns one listener per source and dispose is idempotent and late inert',
    () async {
      var interruptionListens = 0;
      var noisyListens = 0;
      var snapshotListens = 0;
      final countedInterruptions = StreamController<AudioInterruptionEvent>(
        onListen: () => interruptionListens++,
        sync: true,
      );
      final countedNoisy = StreamController<void>(
        onListen: () => noisyListens++,
        sync: true,
      );
      final countedSnapshots = StreamController<PlaybackSnapshot>(
        onListen: () => snapshotListens++,
        sync: true,
      );
      final countedObserver = InterruptionObserver(
        interruptionEvents: countedInterruptions.stream,
        becomingNoisyEvents: countedNoisy.stream,
        confirmedSnapshots: countedSnapshots.stream,
      );
      final events = <InterruptionObservation>[];
      final subscription = countedObserver.observations.listen(events.add);

      expect([interruptionListens, noisyListens, snapshotListens], [1, 1, 1]);
      await Future.wait<void>([
        countedObserver.dispose(),
        countedObserver.dispose(),
      ]);
      countedInterruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      countedNoisy.add(null);
      countedSnapshots.add(PlaybackSnapshot.idle);
      await pumpEventQueue();

      expect(events, isEmpty);
      await subscription.cancel();
      await countedInterruptions.close();
      await countedNoisy.close();
      await countedSnapshots.close();
    },
  );
}

const _testSource =
    // An interruption observer never receives or rewrites command provenance.
    // The integration only needs an existing command source for handler setup.
    CommandSource.ui;
