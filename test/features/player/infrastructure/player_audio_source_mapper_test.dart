// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/player_item_mapper.dart';

void main() {
  group('PlayerItemMapper.toAudioSource', () {
    test('maps URI and tags the source with the matching MediaItem', () {
      final item = _item(
        id: 'content-1',
        audioUri: Uri.parse('https://cdn.example.test/audio-1.mp3'),
        title: 'Episode 1',
        artist: 'The Artist',
        album: 'The Album',
        artUri: Uri.parse('https://cdn.example.test/art-1.png'),
        duration: const Duration(minutes: 3, seconds: 12),
      );

      final source = PlayerItemMapper.toAudioSource(item);

      expect(source, isA<UriAudioSource>());
      final uriSource = source as UriAudioSource;
      expect(uriSource.uri, item.audioUri);
      expect(uriSource.tag, isA<MediaItem>());

      final tag = uriSource.tag as MediaItem;
      expect(tag.id, item.id);
      expect(tag.title, item.title);
      expect(tag.artist, item.artist);
      expect(tag.album, item.album);
      expect(tag.artUri, item.artUri);
      expect(tag.duration, item.duration);
      expect(
        tag.extras![PlayerItemMapper.audioUriExtraKey],
        item.audioUri.toString(),
      );
    });

    test('does not load the URI while mapping', () {
      final source = PlayerItemMapper.toAudioSource(
        _item(
          audioUri: Uri.parse('https://unreachable.example.test/audio.mp3'),
        ),
      );

      expect((source as UriAudioSource).uri.host, 'unreachable.example.test');
    });
  });

  test('maps a queue in the original order', () {
    final items = <PlayerItem>[
      _item(id: 'first', audioUri: Uri.parse('asset:///assets/first.mp3')),
      _item(id: 'second', audioUri: Uri.parse('asset:///assets/second.mp3')),
      _item(id: 'third', audioUri: Uri.parse('file:///tmp/third.mp3')),
    ];

    final sources = PlayerItemMapper.toAudioSources(items);

    expect(
      sources.map((source) => (source as UriAudioSource).uri).toList(),
      items.map((item) => item.audioUri).toList(),
    );
    expect(
      sources
          .map((source) => (source as UriAudioSource).tag as MediaItem)
          .map((tag) => tag.id)
          .toList(),
      items.map((item) => item.id).toList(),
    );
  });
}

PlayerItem _item({
  String id = 'track-1',
  Uri? audioUri,
  String title = 'Track',
  String artist = 'Artist',
  String? album = 'Album',
  Uri? artUri,
  Duration? duration = const Duration(minutes: 2),
}) => PlayerItem(
  id: id,
  audioUri: audioUri ?? Uri.parse('https://cdn.example.test/audio.mp3'),
  title: title,
  artist: artist,
  album: album,
  artUri: artUri ?? Uri.parse('https://cdn.example.test/art.png'),
  duration: duration,
);
