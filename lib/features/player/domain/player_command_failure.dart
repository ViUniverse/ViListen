/// A typed failure for an invalid player command.
///
/// Command failures are boundary validation results. They are intentionally
/// separate from playback failures, which describe errors reported by the
/// playback engine.
final class PlayerCommandFailure implements Exception {
  const PlayerCommandFailure({
    required this.code,
    required this.message,
    required this.command,
  });

  final String code;
  final String message;
  final String command;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerCommandFailure &&
          other.code == code &&
          other.message == message &&
          other.command == command;

  @override
  int get hashCode => Object.hash(code, message, command);
}
