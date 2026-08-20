// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vi_listen/features/player/domain/playback_processing_state.dart';
import 'package:vi_listen/features/player/domain/playback_snapshot.dart';
import 'package:vi_listen/features/player/presentation/widgets/player_artwork.dart';
import '../../support/playback_snapshot_builder.dart';
import '../../support/player_test_data.dart';
import '../../support/player_widget_harness.dart';

void main() {
  testWidgets('uses placeholder when artwork URI is null', (tester) async {
    final resolver = _RecordingResolver();

    await tester.pumpWidget(
      _artworkApp(
        PlayerArtwork(
          size: 80,
          radius: 16,
          imageProviderResolver: resolver.resolve,
        ),
      ),
    );

    expect(find.byKey(_placeholderKey), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(resolver.uris, isEmpty);
  });

  testWidgets('renders valid artwork from the injected provider', (
    tester,
  ) async {
    final resolver = _RecordingResolver();
    final artUri = Uri.parse('https://cdn.example.test/art-a.png');

    await tester.pumpWidget(
      _artworkApp(
        PlayerArtwork(
          size: 80,
          radius: 16,
          artUri: artUri,
          imageProviderResolver: resolver.resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(resolver.uris, [artUri]);
    expect(
      find.byKey(ValueKey<String>('player-artwork-image-$artUri')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Image>(
            find.byKey(ValueKey<String>('player-artwork-image-$artUri')),
          )
          .image,
      isA<MemoryImage>(),
    );
  });

  testWidgets('falls back when the artwork provider fails', (tester) async {
    final artUri = Uri.parse('https://cdn.example.test/broken.png');

    await tester.pumpWidget(
      _artworkApp(
        PlayerArtwork(
          size: 80,
          radius: 16,
          artUri: artUri,
          imageProviderResolver: (_) => const _FailingImageProvider(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(_placeholderKey), findsOneWidget);
  });

  testWidgets('resolves native file artwork without using network', (
    tester,
  ) async {
    final artUri = Uri.file('/tmp/player-artwork.png');

    await tester.pumpWidget(
      _artworkApp(PlayerArtwork(size: 80, radius: 16, artUri: artUri)),
    );

    if (kIsWeb) {
      expect(find.byKey(_placeholderKey), findsOneWidget);
      return;
    }

    final image = tester.widget<Image>(
      find.byKey(ValueKey<String>('player-artwork-image-$artUri')),
    );
    expect(image.image.runtimeType.toString(), 'FileImage');
  });

  testWidgets('resolves again only when the artwork URI changes', (
    tester,
  ) async {
    final resolver = _RecordingResolver();
    final firstUri = Uri.parse('https://cdn.example.test/art-a.png');
    final secondUri = Uri.parse('https://cdn.example.test/art-b.png');

    await tester.pumpWidget(
      _artworkApp(
        PlayerArtwork(
          size: 80,
          radius: 16,
          artUri: firstUri,
          imageProviderResolver: resolver.resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _artworkApp(
        PlayerArtwork(
          size: 80,
          radius: 16,
          artUri: secondUri,
          imageProviderResolver: resolver.resolve,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(resolver.uris, [firstUri, secondUri]);
    expect(
      find.byKey(ValueKey<String>('player-artwork-image-$firstUri')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey<String>('player-artwork-image-$secondUri')),
      findsOneWidget,
    );
  });

  testWidgets('does not resolve again when an ancestor rebuilds', (
    tester,
  ) async {
    final resolver = _RecordingResolver();
    final artUri = Uri.parse('https://cdn.example.test/art-a.png');
    late VoidCallback rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = () => setState(() {});
            return Scaffold(
              body: PlayerArtwork(
                size: 80,
                radius: 16,
                artUri: artUri,
                imageProviderResolver: resolver.resolve,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    rebuild();
    await tester.pumpAndSettle();

    expect(resolver.uris, [artUri]);
  });

  testWidgets('selects artwork by item and preserves the Hero contract', (
    tester,
  ) async {
    final harness = PlayerWidgetHarness();
    final resolver = _RecordingResolver();
    final firstUri = Uri.parse('https://cdn.example.test/art-a.png');
    final secondUri = Uri.parse('https://cdn.example.test/art-b.png');

    try {
      await tester.pumpWidget(
        harness.wrap(
          _artworkApp(
            PlayerArtworkHero(
              size: 80,
              radius: 16,
              imageProviderResolver: resolver.resolve,
            ),
          ),
        ),
      );
      await tester.pump();

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(artUri: firstUri),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      expect(resolver.uris, [firstUri]);

      final hero = tester.widget<Hero>(find.byType(Hero));
      expect(hero.tag, playerArtworkHeroTag);
      expect(hero.createRectTween, isNotNull);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(artUri: firstUri),
          processingState: PlaybackProcessingState.ready,
          position: const Duration(seconds: 1),
        ),
      );
      expect(resolver.uris, [firstUri]);

      await _emitSnapshot(
        tester,
        harness,
        buildPlaybackSnapshot(
          currentItem: testPlayerItem(id: 'track-2', artUri: secondUri),
          processingState: PlaybackProcessingState.ready,
        ),
      );
      expect(resolver.uris, [firstUri, secondUri]);
    } finally {
      await harness.dispose(tester);
    }
  });
}

const _placeholderKey = ValueKey<String>('player-artwork-placeholder');

Widget _artworkApp(Widget child) => MaterialApp(home: Scaffold(body: child));

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

final class _RecordingResolver {
  final List<Uri> uris = <Uri>[];

  ImageProvider<Object> resolve(Uri uri) {
    uris.add(uri);
    return MemoryImage(base64Decode(_pixelPng));
  }
}

final class _FailingImageProvider extends ImageProvider<_FailingImageProvider> {
  const _FailingImageProvider();

  @override
  Future<_FailingImageProvider> obtainKey(ImageConfiguration configuration) =>
      Future<_FailingImageProvider>.error(StateError('artwork load failed'));
}

const _pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
