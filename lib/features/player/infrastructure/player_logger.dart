// SPDX-License-Identifier: Apache-2.0

import 'package:vi_listen/features/player/infrastructure/command_source.dart';

/// Synchronous sink for structured player events.
typedef PlayerLogSink =
    void Function(String event, Map<String, Object?> fields);

/// Typed, privacy-conscious facade for player observability.
///
/// The public API intentionally exposes only the fields approved by PLR-088.
/// A sink is optional and failures are swallowed so logging cannot change a
/// playback command result.
final class PlayerLogger {
  PlayerLogger([this._sink]);

  const PlayerLogger.noop() : _sink = null;

  final PlayerLogSink? _sink;

  void loadStarted({
    required String itemId,
    required int generation,
    required int index,
    required CommandSource source,
  }) {
    _emit('player_load_started', <String, Object?>{
      'itemId': itemId,
      'generation': generation,
      'index': index,
      'source': _sourceName(source),
    });
  }

  void loadReady({
    required String itemId,
    required int generation,
    required int index,
    required int durationMs,
    required int latencyMs,
    required CommandSource source,
  }) {
    _emit('player_load_ready', <String, Object?>{
      'itemId': itemId,
      'generation': generation,
      'index': index,
      'durationMs': durationMs,
      'latencyMs': latencyMs,
      'source': _sourceName(source),
    });
  }

  void play({
    required String itemId,
    required int positionMs,
    required CommandSource source,
  }) {
    _emit('player_play', <String, Object?>{
      'itemId': itemId,
      'positionMs': positionMs,
      'source': _sourceName(source),
    });
  }

  void pause({
    required String itemId,
    required int positionMs,
    required CommandSource source,
  }) {
    _emit('player_pause', <String, Object?>{
      'itemId': itemId,
      'positionMs': positionMs,
      'source': _sourceName(source),
    });
  }

  void seek({
    required int fromMs,
    required int toMs,
    required CommandSource source,
  }) {
    _emit('player_seek', <String, Object?>{
      'fromMs': fromMs,
      'toMs': toMs,
      'source': _sourceName(source),
    });
  }

  void itemChanged({
    required String? oldItemId,
    required String? newItemId,
    required String reason,
    CommandSource? source,
  }) {
    _emit('player_item_changed', <String, Object?>{
      'oldItemId': oldItemId,
      'newItemId': newItemId,
      'reason': reason,
      if (source != null) 'source': _sourceName(source),
    });
  }

  void bufferingStarted({required String? itemId, required int positionMs}) {
    _emit('player_buffering_started', <String, Object?>{
      'itemId': itemId,
      'positionMs': positionMs,
    });
  }

  void bufferingEnded({required String? itemId, required int durationMs}) {
    _emit('player_buffering_ended', <String, Object?>{
      'itemId': itemId,
      'durationMs': durationMs,
    });
  }

  void interrupted({
    required String type,
    required String? itemId,
    required int positionMs,
  }) {
    _emit('player_interrupted', <String, Object?>{
      'type': type,
      'itemId': itemId,
      'positionMs': positionMs,
      'source': _sourceName(CommandSource.interruption),
    });
  }

  void error({
    required String code,
    required String? itemId,
    required bool recoverable,
  }) {
    _emit('player_error', <String, Object?>{
      'code': code,
      'itemId': itemId,
      'recoverable': recoverable,
    });
  }

  void stopped({
    required String? itemId,
    required String reason,
    required CommandSource source,
  }) {
    _emit('player_stopped', <String, Object?>{
      'itemId': itemId,
      'reason': reason,
      'source': _sourceName(source),
    });
  }

  void _emit(String event, Map<String, Object?> fields) {
    final sink = _sink;
    if (sink == null) {
      return;
    }

    try {
      sink(event, Map<String, Object?>.unmodifiable(fields));
    } catch (_) {
      // Observability must never affect playback.
    }
  }

  static String _sourceName(CommandSource source) => switch (source) {
    CommandSource.ui => 'ui',
    CommandSource.systemRemote => 'systemRemote',
    CommandSource.interruption => 'interruption',
  };
}
