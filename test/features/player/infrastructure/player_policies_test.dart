// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_command_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';
import 'package:ten_project_cua_ban/features/player/infrastructure/player_policies.dart';

void main() {
  group('PlayerPolicies', () {
    test('keeps the canonical publication cadences', () {
      expect(
        PlayerPolicies.uiPositionCadence,
        const Duration(milliseconds: 200),
      );
      expect(PlayerPolicies.osPositionCadence, const Duration(seconds: 1));
    });

    test('rejects an empty queue', () {
      expect(
        () => PlayerPolicies.validateQueue(const <PlayerItem>[], isWeb: false),
        _failureCode('emptyQueue'),
      );
    });

    test('rejects an initial index below zero', () {
      expect(
        () => PlayerPolicies.validateQueue(
          [_item()],
          initialIndex: -1,
          isWeb: false,
        ),
        _failureCode('initialIndexOutOfRange'),
      );
    });

    test('rejects an initial index outside the queue', () {
      expect(
        () => PlayerPolicies.validateQueue(
          [_item()],
          initialIndex: 1,
          isWeb: false,
        ),
        _failureCode('initialIndexOutOfRange'),
      );
    });

    test('rejects duplicate item IDs', () {
      expect(
        () => PlayerPolicies.validateQueue([
          _item(id: 'same-id'),
          _item(id: 'same-id', audioUri: Uri.parse('https://example.com/b')),
        ], isWeb: false),
        _failureCode('duplicateItemId'),
      );
    });

    test('accepts and defensively copies a single-item queue', () {
      final item = _item(
        extras: <String, Object?>{
          'nested': <String, Object?>{
            'tags': <Object?>['one', 'two'],
          },
        },
      );
      final input = [item];

      final result = PlayerPolicies.validateQueue(input, isWeb: false);

      expect(result, [item]);
      expect(result, isNot(same(input)));
      expect(result.single, same(item));
      expect(result.single.extras, same(item.extras));
      expect(() => result.add(_item(id: 'second')), throwsUnsupportedError);
    });

    test('accepts a valid multi-item queue and preserves order', () {
      final first = _item(id: 'first');
      final second = _item(
        id: 'second',
        audioUri: Uri.parse('asset:///assets/test_audio/player_fixture_2s.wav'),
      );

      final result = PlayerPolicies.validateQueue(
        [first, second],
        initialIndex: 1,
        isWeb: true,
      );

      expect(result, [first, second]);
      expect(result.map((item) => item.id), ['first', 'second']);
    });

    test('accepts https and canonical asset audio sources on web', () {
      for (final uri in [
        Uri.parse('https://cdn.example.test/audio.mp3'),
        Uri.parse('asset:///assets/test_audio/player_fixture_2s.wav'),
      ]) {
        expect(
          () =>
              PlayerPolicies.validateQueue([_item(audioUri: uri)], isWeb: true),
          returnsNormally,
        );
      }
    });

    test(
      'accepts https, canonical asset, and file audio sources on native',
      () {
        for (final uri in [
          Uri.parse('https://cdn.example.test/audio.mp3'),
          Uri.parse('asset:///assets/test_audio/player_fixture_2s.wav'),
          Uri.parse('file:///tmp/audio.mp3'),
        ]) {
          expect(
            () => PlayerPolicies.validateQueue([
              _item(audioUri: uri),
            ], isWeb: false),
            returnsNormally,
          );
        }
      },
    );

    test('rejects file audio sources on web', () {
      expect(
        () => PlayerPolicies.validateQueue([
          _item(audioUri: Uri.parse('file:///tmp/audio.mp3')),
        ], isWeb: true),
        _failureCode('unsupportedUriScheme'),
      );
    });

    test('rejects http and other audio schemes on every platform', () {
      for (final isWeb in [true, false]) {
        for (final uri in [
          Uri.parse('http://cdn.example.test/audio.mp3'),
          Uri.parse('ftp://cdn.example.test/audio.mp3'),
          Uri.parse('audio.mp3'),
        ]) {
          expect(
            () => PlayerPolicies.validateQueue([
              _item(audioUri: uri),
            ], isWeb: isWeb),
            _failureCode('unsupportedUriScheme'),
          );
        }
      }
    });

    test('accepts only canonical asset audio URIs', () {
      for (final uri in [
        Uri.parse('asset:assets/test_audio/player_fixture_2s.wav'),
        Uri.parse('asset:/assets/test_audio/player_fixture_2s.wav'),
        Uri.parse('asset:////assets/test_audio/player_fixture_2s.wav'),
        Uri.parse('asset:///'),
        Uri.parse('asset://assets/test_audio/player_fixture_2s.wav'),
        Uri.parse('asset:///assets/test_audio/player_fixture_2s.wav?raw=1'),
      ]) {
        expect(
          () => PlayerPolicies.validateQueue([
            _item(audioUri: uri),
          ], isWeb: false),
          _failureCode('unsupportedUriScheme'),
        );
      }
    });

    test('validates artwork URI independently from audio URI', () {
      expect(
        () => PlayerPolicies.validateQueue([
          _item(artUri: Uri.parse('https://cdn.example.test/art.png')),
        ], isWeb: true),
        returnsNormally,
      );
      expect(
        () => PlayerPolicies.validateQueue([
          _item(artUri: Uri.parse('file:///tmp/art.png')),
        ], isWeb: false),
        returnsNormally,
      );

      for (final isWeb in [true, false]) {
        for (final uri in [
          Uri.parse('asset:///assets/art.png'),
          Uri.parse('http://cdn.example.test/art.png'),
          Uri.parse('file:///tmp/art.png'),
        ]) {
          final shouldRejectFile = uri.scheme == 'file' && isWeb;
          if (uri.scheme != 'file' || shouldRejectFile) {
            expect(
              () => PlayerPolicies.validateQueue([
                _item(artUri: uri),
              ], isWeb: isWeb),
              _failureCode('unsupportedUriScheme'),
            );
          }
        }
      }
    });
  });
}

Matcher _failureCode(String code) => throwsA(
  isA<PlayerCommandFailure>()
      .having((failure) => failure.code, 'code', code)
      .having((failure) => failure.command, 'command', 'loadQueue'),
);

PlayerItem _item({
  String id = 'track-1',
  Uri? audioUri,
  Uri? artUri,
  Map<String, Object?> extras = const <String, Object?>{},
}) => PlayerItem(
  id: id,
  audioUri: audioUri ?? Uri.parse('https://cdn.example.test/audio.mp3'),
  title: 'Track',
  artist: 'Artist',
  artUri: artUri,
  extras: extras,
);
