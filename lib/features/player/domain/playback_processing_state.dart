// SPDX-License-Identifier: Apache-2.0

/// Normalized processing state exposed by the player domain.
enum PlaybackProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}
