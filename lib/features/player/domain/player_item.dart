// SPDX-License-Identifier: Apache-2.0

/// Immutable metadata for one playable piece of content.
///
/// The content [id] identifies the item. [audioUri] is the separate source
/// used to play it and must not be used as a substitute for that identity.
final class PlayerItem {
  PlayerItem({
    required this.id,
    required this.audioUri,
    required this.title,
    required this.artist,
    this.album,
    this.artUri,
    this.duration,
    Map<String, Object?> extras = const <String, Object?>{},
  }) : extras = _freezeExtras(extras);

  final String id;
  final Uri audioUri;
  final String title;
  final String artist;
  final String? album;
  final Uri? artUri;
  final Duration? duration;
  final Map<String, Object?> extras;

  static const Object _unset = Object();

  PlayerItem copyWith({
    String? id,
    Uri? audioUri,
    String? title,
    String? artist,
    Object? album = _unset,
    Object? artUri = _unset,
    Object? duration = _unset,
    Map<String, Object?>? extras,
  }) => PlayerItem(
    id: id ?? this.id,
    audioUri: audioUri ?? this.audioUri,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: identical(album, _unset) ? this.album : album as String?,
    artUri: identical(artUri, _unset) ? this.artUri : artUri as Uri?,
    duration: identical(duration, _unset)
        ? this.duration
        : duration as Duration?,
    extras: extras ?? this.extras,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerItem &&
          other.id == id &&
          other.audioUri == audioUri &&
          other.title == title &&
          other.artist == artist &&
          other.album == album &&
          other.artUri == artUri &&
          other.duration == duration &&
          _deepEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(
    id,
    audioUri,
    title,
    artist,
    album,
    artUri,
    duration,
    _deepHash(extras),
  );
}

Map<String, Object?> _freezeExtras(Map<String, Object?> extras) =>
    _deepFreeze(extras, Set<Object>.identity()) as Map<String, Object?>;

Object? _deepFreeze(Object? value, Set<Object> visiting) {
  if (value == null || value is bool || value is int || value is String) {
    return value;
  }

  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'extras',
        'Double values must be finite.',
      );
    }
    return value;
  }

  if (value is Uri || value is Duration) {
    return value;
  }

  if (value is List) {
    if (!visiting.add(value)) {
      throw ArgumentError.value(
        value,
        'extras',
        'Cyclic collections are not allowed.',
      );
    }
    try {
      return List<Object?>.unmodifiable(
        value.map((element) => _deepFreeze(element, visiting)),
      );
    } finally {
      visiting.remove(value);
    }
  }

  if (value is Map) {
    if (!visiting.add(value)) {
      throw ArgumentError.value(
        value,
        'extras',
        'Cyclic collections are not allowed.',
      );
    }
    try {
      final frozen = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError.value(
            entry.key,
            'extras',
            'Map keys must be strings.',
          );
        }
        frozen[entry.key as String] = _deepFreeze(entry.value, visiting);
      }
      return Map<String, Object?>.unmodifiable(frozen);
    } finally {
      visiting.remove(value);
    }
  }

  throw ArgumentError.value(
    value,
    'extras',
    'Only PLR-001 supported values are allowed.',
  );
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }

  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!_deepEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }

  return left == right;
}

int _deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll(<Object?>['list', ...value.map(_deepHash)]);
  }

  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return Object.hash(
      'map',
      value.length,
      Object.hashAll(
        keys.map((key) => Object.hash(key, _deepHash(value[key]))),
      ),
    );
  }

  return value.hashCode;
}
