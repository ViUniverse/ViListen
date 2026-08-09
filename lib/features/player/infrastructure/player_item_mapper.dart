// SPDX-License-Identifier: Apache-2.0

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vi_listen/features/player/domain/player_item.dart';

/// Immutable value projection of the metadata crossing the OS boundary.
///
/// [PlayerItemMapper] uses this same projection for both MediaItem mapping and
/// publication equality so the payload schema cannot drift from its diff.
final class PlayerItemPublicationProjection {
  PlayerItemPublicationProjection._({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artUri,
    required this.duration,
    required Map<String, dynamic> extras,
  }) : extras = Map<String, dynamic>.unmodifiable(extras);

  factory PlayerItemPublicationProjection.from(PlayerItem item) {
    final extras = _scalarExtras(item.extras);
    // The source URI is the reserved payload value, even if domain extras
    // contain a stale value under the same key.
    extras[PlayerItemMapper.audioUriExtraKey] = item.audioUri.toString();

    return PlayerItemPublicationProjection._(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: item.album,
      artUri: item.artUri,
      duration: item.duration,
      extras: extras,
    );
  }

  final String id;
  final String title;
  final String artist;
  final String? album;
  final Uri? artUri;
  final Duration? duration;
  final Map<String, dynamic> extras;

  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: title,
    artist: artist,
    album: album,
    artUri: artUri,
    duration: duration,
    extras: extras,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerItemPublicationProjection &&
          other.id == id &&
          other.title == title &&
          other.artist == artist &&
          other.album == album &&
          other.artUri == artUri &&
          other.duration == duration &&
          _mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artist,
    album,
    artUri,
    duration,
    Object.hashAllUnordered(
      extras.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// Maps domain playback metadata to the metadata understood by audio_service.
abstract final class PlayerItemMapper {
  /// Reserved MediaItem extra containing the actual audio source URI.
  static const String audioUriExtraKey = 'audioUri';

  static MediaItem toMediaItem(PlayerItem item) =>
      PlayerItemPublicationProjection.from(item).toMediaItem();

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

bool _mapEquals(Map<String, dynamic> first, Map<String, dynamic> second) {
  if (identical(first, second)) {
    return true;
  }
  if (first.length != second.length) {
    return false;
  }

  for (final entry in first.entries) {
    if (!second.containsKey(entry.key) || second[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
