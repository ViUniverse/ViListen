import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_processing_state.dart';
import 'package:ten_project_cua_ban/features/player/domain/playback_snapshot.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';
import 'playback_snapshot_builder.dart';
import 'player_test_data.dart';

void main() {
  group('player test data', () {
    test('default snapshot is the safe canonical idle value', () {
      final snapshot = buildPlaybackSnapshot();

      expect(snapshot, PlaybackSnapshot.idle);
      expect(snapshot.progress, 0.0);
      expect(snapshot.remaining, Duration.zero);
      expect(snapshot.hasNext, isFalse);
      expect(snapshot.hasPrevious, isFalse);
      expect(snapshot.isBuffering, isFalse);
      expect(snapshot.isAudible, isFalse);
      expect(snapshot.isCompleted, isFalse);
    });

    test('snapshot builder forwards all domain overrides', () {
      final item = testPlayerItem(id: 'track-2');
      final failure = const PlayerFailure(
        code: 'network',
        message: 'Network unavailable.',
        isRecoverable: true,
        itemId: 'track-2',
      );
      final snapshot = buildPlaybackSnapshot(
        currentItem: item,
        queue: [
          testPlayerItem(id: 'track-1'),
          item,
        ],
        currentIndex: 1,
        processingState: PlaybackProcessingState.buffering,
        playing: true,
        position: const Duration(seconds: 12),
        bufferedPosition: const Duration(seconds: 20),
        duration: const Duration(minutes: 2),
        speed: 1.5,
        repeatMode: PlayerRepeatMode.all,
        shuffleEnabled: true,
        failure: failure,
      );

      expect(snapshot.currentItem, item);
      expect(snapshot.queue, hasLength(2));
      expect(snapshot.currentIndex, 1);
      expect(snapshot.processingState, PlaybackProcessingState.buffering);
      expect(snapshot.playing, isTrue);
      expect(snapshot.position, const Duration(seconds: 12));
      expect(snapshot.bufferedPosition, const Duration(seconds: 20));
      expect(snapshot.duration, const Duration(minutes: 2));
      expect(snapshot.speed, 1.5);
      expect(snapshot.repeatMode, PlayerRepeatMode.all);
      expect(snapshot.shuffleEnabled, isTrue);
      expect(snapshot.failure, failure);
    });

    test('item results do not share mutable nested extras', () {
      final tags = <Object?>['one'];
      final nested = <String, Object?>{'tags': tags};
      final sourceExtras = <String, Object?>{'nested': nested};

      final first = testPlayerItem(extras: sourceExtras);
      final second = testPlayerItem(extras: sourceExtras);

      tags.add('two');
      nested['changed'] = true;
      sourceExtras['outside'] = true;

      expect(first.extras, <String, Object?>{
        'nested': <String, Object?>{
          'tags': <Object?>['one'],
        },
      });
      expect(second.extras, first.extras);
      expect(first.extras, isNot(same(second.extras)));
      expect(first.extras['nested'], isNot(same(second.extras['nested'])));
      expect(
        (first.extras['nested']! as Map<String, Object?>)['tags'],
        isNot(same((second.extras['nested']! as Map<String, Object?>)['tags'])),
      );
    });

    test('snapshot results do not share mutable queue state', () {
      final firstItem = testPlayerItem(id: 'track-1');
      final sourceQueue = <PlayerItem>[firstItem];

      final first = buildPlaybackSnapshot(
        currentItem: firstItem,
        queue: sourceQueue,
        currentIndex: 0,
      );
      final second = buildPlaybackSnapshot(
        currentItem: firstItem,
        queue: sourceQueue,
        currentIndex: 0,
      );

      sourceQueue.add(testPlayerItem(id: 'track-2'));

      expect(first.queue, [firstItem]);
      expect(second.queue, [firstItem]);
      expect(first.queue, isNot(same(second.queue)));
      expect(() => first.queue.add(testPlayerItem()), throwsUnsupportedError);
      expect(() => second.queue.add(testPlayerItem()), throwsUnsupportedError);
    });
  });
}
