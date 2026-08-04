import 'package:ten_project_cua_ban/features/player/application/player_command_policies.dart';

/// Pure position and previous-navigation policies for playback commands.
///
/// This class only calculates decisions. Engine calls, command failures, and
/// snapshot publication remain the responsibility of the handler.
abstract final class PlaybackPositionPolicy {
  /// Clamps [target] to the inclusive range from zero to [duration].
  ///
  /// A non-positive duration represents an unknown duration and returns null.
  static Duration? clampSeek({
    required Duration target,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) {
      return null;
    }
    if (target <= Duration.zero) {
      return Duration.zero;
    }
    if (target >= duration) {
      return duration;
    }
    return target;
  }

  /// Computes [position] + [offset] and clamps the result to the duration.
  static Duration? skipTarget({
    required Duration position,
    required Duration offset,
    required Duration duration,
  }) => clampSeek(target: position + offset, duration: duration);

  /// Decides whether Previous restarts the current item or navigates back.
  ///
  /// Invalid queue state is a safe no-op. Repeat and shuffle boundary rules
  /// are applied by the later navigation operation using the effective queue.
  static PreviousDecision previous({
    required Duration position,
    required int? currentIndex,
    required int queueLength,
  }) {
    final index = currentIndex;
    if (queueLength <= 0 ||
        index == null ||
        index < 0 ||
        index >= queueLength) {
      return const PreviousDecision.noOp();
    }

    if (position > PlayerCommandPolicies.previousRestartThreshold) {
      return const PreviousDecision.restartCurrent();
    }

    if (index == 0) {
      return const PreviousDecision.noOp();
    }

    return PreviousDecision.navigateToIndex(index - 1);
  }
}

enum PreviousDecisionKind { restartCurrent, navigateToIndex, noOp }

final class PreviousDecision {
  const PreviousDecision._(this.kind, this.targetIndex);

  const PreviousDecision.restartCurrent()
    : this._(PreviousDecisionKind.restartCurrent, null);

  const PreviousDecision.noOp() : this._(PreviousDecisionKind.noOp, null);

  const PreviousDecision.navigateToIndex(int index)
    : this._(PreviousDecisionKind.navigateToIndex, index);

  final PreviousDecisionKind kind;
  final int? targetIndex;
}
