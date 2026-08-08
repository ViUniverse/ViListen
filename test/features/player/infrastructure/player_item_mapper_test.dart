// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/player_item_mapper.dart';

void main() {
  group('PlayerItemMapper', () {
    test(
      'maps metadata fields and keeps content ID separate from audio URI',
      () {
        final item = _item(
          id: 'content-1',
          audioUri: Uri.parse('https://cdn.example.test/audio-1.mp3'),
          title: 'Episode 1',
          artist: 'The Artist',
          album: 'The Album',
          artUri: Uri.parse('https://cdn.example.test/art-1.png'),
          duration: const Duration(minutes: 3, seconds: 12),
        );

        final mediaItem = PlayerItemMapper.toMediaItem(item);

        expect(mediaItem.id, 'content-1');
        expect(mediaItem.title, 'Episode 1');
        expect(mediaItem.artist, 'The Artist');
        expect(mediaItem.album, 'The Album');
        expect(
          mediaItem.artUri,
          Uri.parse('https://cdn.example.test/art-1.png'),
        );
        expect(mediaItem.duration, const Duration(minutes: 3, seconds: 12));
        expect(
          mediaItem.extras![PlayerItemMapper.audioUriExtraKey],
          'https://cdn.example.test/audio-1.mp3',
        );
        expect(mediaItem.id, isNot(mediaItem.extras!['audioUri']));
      },
    );

    test('preserves nullable metadata fields', () {
      final mediaItem = PlayerItemMapper.toMediaItem(
        _item(album: null, artUri: null, duration: null),
      );

      expect(mediaItem.album, isNull);
      expect(mediaItem.artUri, isNull);
      expect(mediaItem.duration, isNull);
    });

    test('forwards only audio_service-compatible scalar extras', () {
      final mediaItem = PlayerItemMapper.toMediaItem(
        _item(
          extras: <String, Object?>{
            'nullable': null,
            'string': 'value',
            'int': 12,
            'double': 1.5,
            'bool': true,
            'uri': Uri.parse('https://cdn.example.test/extra'),
            'duration': const Duration(seconds: 12),
            'nestedList': <Object?>[true, 1],
            'nestedMap': <String, Object?>{'value': 'nested'},
          },
        ),
      );

      expect(mediaItem.extras, <String, dynamic>{
        'string': 'value',
        'int': 12,
        'double': 1.5,
        'bool': true,
        'audioUri': 'https://cdn.example.test/audio.mp3',
      });
      expect(
        mediaItem.extras!.values,
        everyElement(
          anyOf(isA<int>(), isA<String>(), isA<bool>(), isA<double>()),
        ),
      );
    });

    test(
      'does not allow domain extras to overwrite the reserved audio URI',
      () {
        final mediaItem = PlayerItemMapper.toMediaItem(
          _item(
            audioUri: Uri.parse('asset:///assets/actual.mp3'),
            extras: <String, Object?>{
              'audioUri': 'stale-audio-uri',
              'label': 'preserved',
            },
          ),
        );

        expect(
          mediaItem.extras![PlayerItemMapper.audioUriExtraKey],
          'asset:///assets/actual.mp3',
        );
        expect(mediaItem.extras!['label'], 'preserved');
      },
    );

    test('keeps valid audio URI forms unchanged', () {
      for (final uri in <Uri>[
        Uri.parse('https://cdn.example.test/audio.mp3'),
        Uri.parse('asset:///assets/test_audio/player_fixture_2s.wav'),
        Uri.parse('file:///tmp/audio.mp3'),
      ]) {
        final mediaItem = PlayerItemMapper.toMediaItem(_item(audioUri: uri));

        expect(
          mediaItem.extras![PlayerItemMapper.audioUriExtraKey],
          uri.toString(),
        );
      }
    });
  });
}

PlayerItem _item({
  Object? artUri = _unset,
  String id = 'track-1',
  Uri? audioUri,
  String title = 'Track',
  String artist = 'Artist',
  String? album = 'Album',
  Duration? duration = const Duration(minutes: 2),
  Map<String, Object?> extras = const <String, Object?>{},
}) => PlayerItem(
  id: id,
  audioUri: audioUri ?? Uri.parse('https://cdn.example.test/audio.mp3'),
  title: title,
  artist: artist,
  album: album,
  artUri: identical(artUri, _unset)
      ? Uri.parse('https://cdn.example.test/art.png')
      : artUri as Uri?,
  duration: duration,
  extras: extras,
);

const Object _unset = Object();
