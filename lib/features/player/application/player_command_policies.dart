// SPDX-License-Identifier: Apache-2.0

import 'package:vi_listen/features/player/domain/player_repeat_mode.dart';

/// Shared application-level policies for player commands.
///
/// Infrastructure may use these values when translating commands to an
/// engine. Presentation reaches them through application commands and state;
/// this policy must not contain UI cadence or engine-specific behavior.
abstract final class PlayerCommandPolicies {
  static const skipInterval = Duration(seconds: 10);
  static const previousRestartThreshold = Duration(seconds: 3);

  static const minSpeed = 0.5;
  static const maxSpeed = 2.0;

  static const speedPresets = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  static const repeatCycle = <PlayerRepeatMode>[
    PlayerRepeatMode.off,
    PlayerRepeatMode.one,
    PlayerRepeatMode.all,
  ];

  /// Returns whether [speed] is a finite value in the closed API range.
  ///
  /// The API range is intentionally broader than [speedPresets]; callers may
  /// provide any finite value between the two bounds.
  static bool isSpeedInRange(double speed) =>
      speed.isFinite && speed >= minSpeed && speed <= maxSpeed;

  /// Returns the next repeat mode in the canonical application cycle.
  static PlayerRepeatMode nextRepeatMode(PlayerRepeatMode current) {
    final index = repeatCycle.indexOf(current);
    return repeatCycle[(index + 1) % repeatCycle.length];
  }
}
