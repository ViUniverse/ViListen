// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/infrastructure/app_audio_handler.dart';
import 'package:vi_listen/features/player/infrastructure/command_source.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_player_clock.dart';
import '../support/player_test_data.dart';

void main() {
  late FakePlaybackEngine engine;
  late AppAudioHandler handler;
  late List<({String command, CommandSource source})> observedCommands;

  setUp(() {
    engine = FakePlaybackEngine();
    observedCommands = <({String command, CommandSource source})>[];
    handler = AppAudioHandler(engine, FakePlayerClock(), (command, source) {
      observedCommands.add((command: command, source: source));
    });
  });

  tearDown(() async {
    await handler.dispose();
  });

  test('rewind uses one -10 second skipBy seek', () async {
    await _load(handler, engine);
    observedCommands.clear();

    await handler.rewind();

    final seekCalls = engine.calls
        .where((call) => call.name == 'seek')
        .toList();
    expect(seekCalls, hasLength(1));
    expect(seekCalls.single.arguments['position'], const Duration(seconds: 20));
    expect(seekCalls.single.arguments['index'], isNull);
    expect(observedCommands, [
      (command: 'skipBy', source: CommandSource.systemRemote),
    ]);
  });

  test('fast-forward uses one +10 second skipBy seek', () async {
    await _load(handler, engine);
    observedCommands.clear();

    await handler.fastForward();

    final seekCalls = engine.calls
        .where((call) => call.name == 'seek')
        .toList();
    expect(seekCalls, hasLength(1));
    expect(seekCalls.single.arguments['position'], const Duration(seconds: 40));
    expect(seekCalls.single.arguments['index'], isNull);
    expect(observedCommands, [
      (command: 'skipBy', source: CommandSource.systemRemote),
    ]);
  });
}

Future<void> _load(AppAudioHandler handler, FakePlaybackEngine engine) async {
  final load = handler.handleLoadQueue(
    [testPlayerItem(id: 'remote-seek-track')],
    0,
    false,
    CommandSource.ui,
  );
  await pumpEventQueue();
  engine.emitDuration(const Duration(seconds: 60));
  engine.emitPosition(const Duration(seconds: 30));
  engine.loadRequests.single.complete();
  await load;
  await pumpEventQueue();
}
