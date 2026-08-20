// SPDX-License-Identifier: Apache-2.0

/// Formats an elapsed playback duration as `M:SS` or `H:MM:SS`.
String formatElapsed(Duration duration) => _formatClock(duration);

/// Formats a remaining playback duration with a negative prefix.
String formatRemaining(Duration duration) => '-${_formatClock(duration)}';

String _formatClock(Duration duration) {
  final boundedDuration = duration < Duration.zero ? Duration.zero : duration;
  final totalSeconds = boundedDuration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;

  if (hours > 0) {
    return '$hours:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  final totalMinutes = totalSeconds ~/ Duration.secondsPerMinute;
  return '$totalMinutes:${seconds.toString().padLeft(2, '0')}';
}
