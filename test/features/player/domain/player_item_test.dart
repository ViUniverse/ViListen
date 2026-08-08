// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';

void main() {
  group('PlayerItem', () {
    test('retains all fields and keeps content id separate from audio URI', () {
      final item = _item(
        id: 'content-1',
        audioUri: Uri.parse('https://cdn.example.test/audio-1.mp3'),
      );

      expect(item.id, 'content-1');
      expect(item.audioUri, Uri.parse('https://cdn.example.test/audio-1.mp3'));
      expect(item.title, 'Episode 1');
      expect(item.artist, 'The Artist');
      expect(item.album, 'The Album');
      expect(item.artUri, Uri.parse('https://cdn.example.test/art-1.png'));
      expect(item.duration, const Duration(minutes: 3, seconds: 12));
      expect(item.extras['category'], 'podcast');
    });

    test('uses every field for equality and hashCode', () {
      final item = _item();
      final equalItem = _item(
        extras: <String, Object?>{
          'category': 'podcast',
          'nested': <String, Object?>{
            'tags': <Object?>['one', 'two'],
          },
        },
      );

      expect(item, equalItem);
      expect(item.hashCode, equalItem.hashCode);

      expect(item, isNot(_item(id: 'different-id')));
      expect(item, isNot(_item(audioUri: Uri.parse('asset:///other.mp3'))));
      expect(item, isNot(_item(title: 'Different title')));
      expect(item, isNot(_item(artist: 'Different artist')));
      expect(item, isNot(_item(album: 'Different album')));
      expect(
        item,
        isNot(_item(artUri: Uri.parse('https://cdn.example.test/other.png'))),
      );
      expect(item, isNot(_item(duration: const Duration(minutes: 4))));
      expect(
        item,
        isNot(
          _item(
            extras: <String, Object?>{
              'category': 'different',
              'nested': <String, Object?>{
                'tags': <Object?>['one', 'two'],
              },
            },
          ),
        ),
      );
    });

    test(
      'deep equality ignores map insertion order but preserves list order',
      () {
        final first = _item(
          extras: <String, Object?>{
            'first': 1,
            'second': <Object?>['a', 'b'],
          },
        );
        final sameValuesDifferentMapOrder = _item(
          extras: <String, Object?>{
            'second': <Object?>['a', 'b'],
            'first': 1,
          },
        );
        final differentListOrder = _item(
          extras: <String, Object?>{
            'first': 1,
            'second': <Object?>['b', 'a'],
          },
        );

        expect(first, sameValuesDifferentMapOrder);
        expect(first.hashCode, sameValuesDifferentMapOrder.hashCode);
        expect(first, isNot(differentListOrder));
      },
    );

    test('copyWith changes requested fields and preserves the rest', () {
      final item = _item();

      final copy = item.copyWith(id: 'content-2', title: 'Episode 2');

      expect(copy.id, 'content-2');
      expect(copy.title, 'Episode 2');
      expect(copy.audioUri, item.audioUri);
      expect(copy.artist, item.artist);
      expect(copy.album, item.album);
      expect(copy.artUri, item.artUri);
      expect(copy.duration, item.duration);
      expect(copy.extras, item.extras);
      expect(item.id, 'content-1');
      expect(item.title, 'Episode 1');
    });

    test('copyWith can clear nullable fields', () {
      final item = _item();

      final copy = item.copyWith(album: null, artUri: null, duration: null);

      expect(copy.album, isNull);
      expect(copy.artUri, isNull);
      expect(copy.duration, isNull);
    });

    test('deep-copies mutable input collections', () {
      final tags = <Object?>['one'];
      final nested = <String, Object?>{'tags': tags};
      final sourceExtras = <String, Object?>{'nested': nested};
      final item = _item(extras: sourceExtras);

      tags.add('two');
      nested['addedLater'] = true;
      sourceExtras['replaced'] = 'outside';

      expect(item.extras, <String, Object?>{
        'nested': <String, Object?>{
          'tags': <Object?>['one'],
        },
      });
    });

    test('does not expose mutable collections through extras', () {
      final item = _item();
      final nested = item.extras['nested']! as Map<String, Object?>;
      final tags = nested['tags']! as List<Object?>;

      expect(() => item.extras['new'] = true, throwsUnsupportedError);
      expect(() => nested['new'] = true, throwsUnsupportedError);
      expect(() => tags.add('three'), throwsUnsupportedError);
    });

    test('rejects values outside the PLR-001 extras grammar', () {
      expect(
        () => _item(extras: <String, Object?>{'value': Object()}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => _item(extras: <String, Object?>{'value': <Object?>{}}),
        throwsA(isA<ArgumentError>()),
      );
      final invalidMap = <Object?, Object?>{1: 'non-string key'};
      final extras = <String, Object?>{'nested': invalidMap};
      expect(() => _item(extras: extras), throwsA(isA<ArgumentError>()));
      expect(
        () => _item(extras: <String, Object?>{'value': double.nan}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => _item(extras: <String, Object?>{'value': double.infinity}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () =>
            _item(extras: <String, Object?>{'value': double.negativeInfinity}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => _item(
          extras: <String, Object?>{
            'value': <Object?>['ok', <Object?>[]],
          },
        ),
        returnsNormally,
      );
    });

    test('rejects a direct cyclic list in extras', () {
      final cycle = <Object?>[];
      cycle.add(cycle);

      expect(
        () => _item(extras: <String, Object?>{'cycle': cycle}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a nested cyclic map in extras', () {
      final root = <String, Object?>{};
      final child = <String, Object?>{'root': root};
      root['child'] = child;

      expect(
        () => _item(extras: <String, Object?>{'nested': root}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('does not derive id from audioUri', () {
      final first = _item(
        id: 'content-1',
        audioUri: Uri.parse('https://cdn.example.test/shared.mp3'),
      );
      final second = _item(
        id: 'content-2',
        audioUri: Uri.parse('https://cdn.example.test/shared.mp3'),
      );

      expect(first.audioUri, second.audioUri);
      expect(first.id, isNot(second.id));
      expect(first, isNot(second));
    });
  });
}

PlayerItem _item({
  String id = 'content-1',
  Uri? audioUri,
  String title = 'Episode 1',
  String artist = 'The Artist',
  String? album = 'The Album',
  Uri? artUri,
  Duration? duration = const Duration(minutes: 3, seconds: 12),
  Map<String, Object?> extras = const <String, Object?>{
    'category': 'podcast',
    'nested': <String, Object?>{
      'tags': <Object?>['one', 'two'],
    },
  },
}) => PlayerItem(
  id: id,
  audioUri: audioUri ?? Uri.parse('https://cdn.example.test/audio-1.mp3'),
  title: title,
  artist: artist,
  album: album,
  artUri: artUri ?? Uri.parse('https://cdn.example.test/art-1.png'),
  duration: duration,
  extras: extras,
);
