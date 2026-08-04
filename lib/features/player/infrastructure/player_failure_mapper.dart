import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_failure.dart';

/// Identifies the load operation that produced an engine error.
///
/// A stale load is intentionally not converted into a user-visible failure.
enum PlayerFailureContext { runtime, initialLoad, replaceLoad, staleLoad }

/// Platform that produced the raw engine error.
///
/// The integer carried by [PlayerException] has different meanings on each
/// platform, so callers must provide the origin before numeric mapping is
/// attempted.
enum PlayerFailurePlatform { android, apple, web, unknown }

/// Converts engine and platform errors into safe domain failures.
///
/// The mapper never performs I/O and never stores the original exception. The
/// caller supplies [itemId] from its active or pending playback context because
/// an engine source index is not a stable content ID.
final class PlayerFailureMapper {
  const PlayerFailureMapper();

  PlayerFailure? map(
    Object error, {
    required PlayerFailureContext context,
    required PlayerFailurePlatform platform,
    String? itemId,
  }) {
    if (context == PlayerFailureContext.staleLoad ||
        error is PlayerInterruptedException ||
        _isInterruptedPlatformError(error)) {
      return null;
    }

    final kind = _classify(error, platform);
    return switch (kind) {
      _FailureKind.interrupted => null,
      _FailureKind.network => PlayerFailure(
        code: 'network',
        message: 'Network unavailable.',
        isRecoverable: true,
        itemId: itemId,
      ),
      _FailureKind.notFound => PlayerFailure(
        code: 'not_found',
        message: 'Audio source not found.',
        isRecoverable: false,
        itemId: itemId,
      ),
      _FailureKind.unsupportedFormat => PlayerFailure(
        code: 'unsupported_format',
        message: 'Audio format is not supported.',
        isRecoverable: false,
        itemId: itemId,
      ),
      _FailureKind.audioOutput => PlayerFailure(
        code: 'audio_output',
        message: 'Audio output is unavailable.',
        isRecoverable: true,
        itemId: itemId,
      ),
      _FailureKind.unknown => PlayerFailure(
        code: 'unknown_engine',
        message: 'Playback failed.',
        isRecoverable: false,
        itemId: itemId,
      ),
    };
  }

  static _FailureKind _classify(Object error, PlayerFailurePlatform platform) {
    if (error is TimeoutException) {
      return _FailureKind.network;
    }

    final code = _numericCode(error);
    final platformKind = _classifyPlatformCode(platform, code);
    if (platformKind == _FailureKind.interrupted) {
      return _FailureKind.interrupted;
    }

    final messageKind = _classifyMessage(_errorSignal(error));
    if (platformKind != null && !_canRefinePlatformCode(platform, code)) {
      return platformKind;
    }

    return messageKind ?? platformKind ?? _FailureKind.unknown;
  }

  static String _errorSignal(Object error) {
    final message = switch (error) {
      PlayerException(:final message) => message,
      PlatformException(:final message) => message,
      _ => error.toString(),
    };
    return (message ?? '').toLowerCase();
  }

  static _FailureKind? _classifyMessage(String signal) {
    if (_containsAny(signal, const <String>[
      '404',
      'not found',
      'not_found',
      'no such file',
    ])) {
      return _FailureKind.notFound;
    }
    if (_containsAny(signal, const <String>[
      'unsupported',
      'codec',
      'decoder',
      'format',
      'mime type',
      'content type',
    ])) {
      return _FailureKind.unsupportedFormat;
    }
    if (_containsAny(signal, const <String>[
      'audio output',
      'audio device',
      'audio track',
      'audiotrack',
      'output device',
      'no output',
      'audio route',
    ])) {
      return _FailureKind.audioOutput;
    }
    if (_containsAny(signal, const <String>[
      'network',
      'timeout',
      'timed out',
      'connection',
      'unreachable',
      'dns',
      'offline',
      'socket',
      'connection reset',
    ])) {
      return _FailureKind.network;
    }
    return null;
  }

  static _FailureKind? _classifyPlatformCode(
    PlayerFailurePlatform platform,
    int? code,
  ) {
    if (code == null) {
      return null;
    }

    return switch (platform) {
      PlayerFailurePlatform.web => _webCodes[code],
      PlayerFailurePlatform.android => _androidCodes[code],
      PlayerFailurePlatform.apple => _appleCodes[code],
      PlayerFailurePlatform.unknown => null,
    };
  }

  static bool _canRefinePlatformCode(
    PlayerFailurePlatform platform,
    int? code,
  ) =>
      platform == PlayerFailurePlatform.android &&
      (code == 0 || code == 1 || code == 2);

  static int? _numericCode(Object error) {
    return switch (error) {
      PlayerException(:final code) => code,
      PlatformException(:final code) => int.tryParse(code),
      _ => null,
    };
  }

  static bool _isInterruptedPlatformError(Object error) =>
      error is PlatformException && error.code.toLowerCase() == 'abort';

  static bool _containsAny(String value, List<String> signals) =>
      signals.any(value.contains);
}

enum _FailureKind {
  network,
  notFound,
  unsupportedFormat,
  audioOutput,
  interrupted,
  unknown,
}

// just_audio_web forwards the browser MediaError code. The generic browser
// message is not enough to classify the error, so these values are mapped only
// when the caller identifies the origin as Web.
const _webCodes = <int, _FailureKind>{
  1: _FailureKind.interrupted, // MEDIA_ERR_ABORTED
  2: _FailureKind.network, // MEDIA_ERR_NETWORK
  3: _FailureKind.unsupportedFormat, // MEDIA_ERR_DECODE
  4: _FailureKind.unsupportedFormat, // MEDIA_ERR_SRC_NOT_SUPPORTED
};

// Android ExoPlaybackException types are 0/1/2. Type SOURCE is a generic
// source/load failure; in the absence of a more specific message it follows
// the existing network/load fallback. Media3 error codes are also included for
// non-Exo PlaybackException paths used by just_audio.
const _androidCodes = <int, _FailureKind>{
  0: _FailureKind.network, // ExoPlaybackException.TYPE_SOURCE
  2001: _FailureKind.network, // ERROR_CODE_IO_NETWORK_CONNECTION_FAILED
  2002: _FailureKind.network, // ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT
  2003:
      _FailureKind.unsupportedFormat, // ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE
  2004: _FailureKind.network, // ERROR_CODE_IO_BAD_HTTP_STATUS
  2005: _FailureKind.notFound, // ERROR_CODE_IO_FILE_NOT_FOUND
  3003: _FailureKind
      .unsupportedFormat, // ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED
  3004:
      _FailureKind.unsupportedFormat, // ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED
  4001: _FailureKind.unsupportedFormat, // ERROR_CODE_DECODER_INIT_FAILED
  4002: _FailureKind.unsupportedFormat, // ERROR_CODE_DECODER_QUERY_FAILED
  4003: _FailureKind.unsupportedFormat, // ERROR_CODE_DECODING_FAILED
  4004: _FailureKind
      .unsupportedFormat, // ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES
  5001: _FailureKind.audioOutput, // ERROR_CODE_AUDIO_TRACK_INIT_FAILED
  5002: _FailureKind.audioOutput, // ERROR_CODE_AUDIO_TRACK_WRITE_FAILED
  5003: _FailureKind.audioOutput, // ERROR_CODE_AUDIO_TRACK_OFFLOAD_INIT_FAILED
  5004: _FailureKind.audioOutput, // ERROR_CODE_AUDIO_TRACK_OFFLOAD_WRITE_FAILED
};

// Apple errors are NSError/AVFoundation domains surfaced as integer codes by
// just_audio. These are intentionally separate from Android/Web integers.
const _appleCodes = <int, _FailureKind>{
  -1001: _FailureKind.network, // NSURLErrorTimedOut
  -1003: _FailureKind.network, // NSURLErrorCannotFindHost
  -1004: _FailureKind.network, // NSURLErrorCannotConnectToHost
  -1005: _FailureKind.network, // NSURLErrorNetworkConnectionLost
  -1009: _FailureKind.network, // NSURLErrorNotConnectedToInternet
  -1011: _FailureKind.network, // NSURLErrorBadServerResponse
  -1100: _FailureKind.notFound, // NSFileNoSuchFileError
  -11828: _FailureKind.unsupportedFormat, // AVErrorFileFormatNotRecognized
  -11833: _FailureKind.unsupportedFormat, // AVErrorDecoderNotFound
  -11864: _FailureKind.unsupportedFormat, // AVErrorContentIsNotSupported
};
