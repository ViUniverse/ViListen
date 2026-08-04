import 'package:ten_project_cua_ban/features/player/domain/player_command_failure.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_item.dart';

/// Infrastructure policies shared by queue loading and publication layers.
///
/// Command intervals and speed ranges belong to the application policy layer.
/// This class only owns source validation, queue boundary validation, and
/// publication cadence.
abstract final class PlayerPolicies {
  static const uiPositionCadence = Duration(milliseconds: 200);
  static const osPositionCadence = Duration(seconds: 1);

  /// Validates and defensively copies a queue before a load is started.
  ///
  /// The [PlayerItem] constructor is the ownership boundary for `extras`, so
  /// malformed extras cannot reach this API. PlayerItem owns the item graph's
  /// immutability; this method only copies the queue container.
  static List<PlayerItem> validateQueue(
    List<PlayerItem> items, {
    int initialIndex = 0,
    required bool isWeb,
  }) {
    if (items.isEmpty) {
      throw _failure(code: 'emptyQueue', message: 'Queue cannot be empty.');
    }

    if (initialIndex < 0 || initialIndex >= items.length) {
      throw _failure(
        code: 'initialIndexOutOfRange',
        message: 'Initial index is outside the queue.',
      );
    }

    final ids = <String>{};
    for (final item in items) {
      if (!ids.add(item.id)) {
        throw _failure(
          code: 'duplicateItemId',
          message: 'Queue item IDs must be unique.',
        );
      }

      _validateAudioUri(item.audioUri, isWeb: isWeb);
      if (item.artUri != null) {
        _validateArtUri(item.artUri!, isWeb: isWeb);
      }
    }

    return List<PlayerItem>.unmodifiable(items);
  }

  static void _validateAudioUri(Uri uri, {required bool isWeb}) {
    final valid = switch (uri.scheme.toLowerCase()) {
      'https' => _hasAuthority(uri),
      'asset' => _isCanonicalAssetUri(uri),
      'file' => !isWeb && uri.path.isNotEmpty,
      _ => false,
    };

    if (!valid) {
      throw _failure(
        code: 'unsupportedUriScheme',
        message: 'Audio source URI is not supported.',
      );
    }
  }

  static void _validateArtUri(Uri uri, {required bool isWeb}) {
    final valid = switch (uri.scheme.toLowerCase()) {
      'https' => _hasAuthority(uri),
      'file' => !isWeb && uri.path.isNotEmpty,
      _ => false,
    };

    if (!valid) {
      throw _failure(
        code: 'unsupportedUriScheme',
        message: 'Artwork URI is not supported.',
      );
    }
  }

  static bool _hasAuthority(Uri uri) => uri.host.isNotEmpty;

  static bool _isCanonicalAssetUri(Uri uri) =>
      uri.hasAuthority &&
      uri.host.isEmpty &&
      uri.path.startsWith('/') &&
      !uri.path.startsWith('//') &&
      uri.path.length > 1 &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty;

  static PlayerCommandFailure _failure({
    required String code,
    required String message,
  }) =>
      PlayerCommandFailure(code: code, message: message, command: 'loadQueue');
}
