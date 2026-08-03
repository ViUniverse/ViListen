import 'package:flutter_test/flutter_test.dart';
import 'package:ten_project_cua_ban/features/player/application/player_command_policies.dart';
import 'package:ten_project_cua_ban/features/player/domain/player_repeat_mode.dart';

void main() {
  group('PlayerCommandPolicies', () {
    test('keeps the canonical command intervals', () {
      expect(PlayerCommandPolicies.skipInterval, const Duration(seconds: 10));
      expect(
        PlayerCommandPolicies.previousRestartThreshold,
        const Duration(seconds: 3),
      );
    });

    test('exposes the canonical speed presets in order', () {
      expect(PlayerCommandPolicies.speedPresets, const [
        0.5,
        0.75,
        1.0,
        1.25,
        1.5,
        1.75,
        2.0,
      ]);
    });

    test('accepts every finite speed in the closed API range', () {
      expect(PlayerCommandPolicies.isSpeedInRange(0.5), isTrue);
      expect(PlayerCommandPolicies.isSpeedInRange(1.1), isTrue);
      expect(PlayerCommandPolicies.isSpeedInRange(2.0), isTrue);

      expect(PlayerCommandPolicies.isSpeedInRange(0.499), isFalse);
      expect(PlayerCommandPolicies.isSpeedInRange(2.001), isFalse);
      expect(PlayerCommandPolicies.isSpeedInRange(double.nan), isFalse);
      expect(PlayerCommandPolicies.isSpeedInRange(double.infinity), isFalse);
      expect(
        PlayerCommandPolicies.isSpeedInRange(double.negativeInfinity),
        isFalse,
      );
    });

    test('keeps repeat modes in the canonical cycle order', () {
      expect(PlayerCommandPolicies.repeatCycle, const [
        PlayerRepeatMode.off,
        PlayerRepeatMode.one,
        PlayerRepeatMode.all,
      ]);

      expect(
        PlayerCommandPolicies.nextRepeatMode(PlayerRepeatMode.off),
        PlayerRepeatMode.one,
      );
      expect(
        PlayerCommandPolicies.nextRepeatMode(PlayerRepeatMode.one),
        PlayerRepeatMode.all,
      );
      expect(
        PlayerCommandPolicies.nextRepeatMode(PlayerRepeatMode.all),
        PlayerRepeatMode.off,
      );
    });
  });
}
