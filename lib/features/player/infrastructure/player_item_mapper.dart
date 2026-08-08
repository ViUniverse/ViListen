// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';

/// Maps domain playback metadata to the metadata understood by audio_service.
abstract final class PlayerItemMapper {
  /// Reserved MediaItem extra containing the actual audio source URI.
  static const String audioUriExtraKey = 'audioUri';

  static MediaItem toMediaItem(PlayerItem item) => MediaItem(
    id: item.id,
    title: item.title,
    artist: item.artist,
    album: item.album,
    artUri: item.artUri,
    duration: item.duration,
    extras: <String, dynamic>{
      ..._scalarExtras(item.extras),
      // MediaItem extras cross a platform boundary and only support scalar
      // values. The source URI is therefore serialized as a String.
      audioUriExtraKey: item.audioUri.toString(),
    },
  );

  /// Maps the playable URI and the same metadata used by audio_service.
  ///
  /// [AudioSource.uri] only constructs the source. Loading, including any
  /// asset or network I/O, is owned by the playback engine.
  static AudioSource toAudioSource(PlayerItem item) =>
      AudioSource.uri(item.audioUri, tag: toMediaItem(item));

  /// Maps a queue without changing its domain order.
  static List<AudioSource> toAudioSources(Iterable<PlayerItem> items) =>
      List<AudioSource>.unmodifiable(items.map((item) => toAudioSource(item)));
}

/// Returns only extras supported by [MediaItem.extras].
///
/// Complex values remain available on [PlayerItem] but are intentionally not
/// copied into OS metadata. [MediaItem.duration] is mapped through its typed
/// field rather than through extras.
Map<String, dynamic> _scalarExtras(Map<String, Object?> extras) {
  final scalarExtras = <String, dynamic>{};
  for (final entry in extras.entries) {
    final value = entry.value;
    if (value is int || value is String || value is bool || value is double) {
      scalarExtras[entry.key] = value;
    }
  }
  return scalarExtras;
}
