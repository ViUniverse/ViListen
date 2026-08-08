// SPDX-License-Identifier: Apache-2.0

/// A normalized playback failure exposed by the player domain.
///
/// Runtime and platform errors are mapped to this value object before they
/// become part of playback state. Exception objects and stack traces stay at
/// the infrastructure boundary.
final class PlayerFailure {
  const PlayerFailure({
    required this.code,
    required this.message,
    required this.isRecoverable,
    this.itemId,
  });

  final String code;
  final String message;
  final bool isRecoverable;
  final String? itemId;

  static const Object _unset = Object();

  PlayerFailure copyWith({
    String? code,
    String? message,
    bool? isRecoverable,
    Object? itemId = _unset,
  }) => PlayerFailure(
    code: code ?? this.code,
    message: message ?? this.message,
    isRecoverable: isRecoverable ?? this.isRecoverable,
    itemId: identical(itemId, _unset) ? this.itemId : itemId as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerFailure &&
          other.code == code &&
          other.message == message &&
          other.isRecoverable == isRecoverable &&
          other.itemId == itemId;

  @override
  int get hashCode => Object.hash(code, message, isRecoverable, itemId);
}
