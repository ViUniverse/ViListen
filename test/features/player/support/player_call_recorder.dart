// SPDX-License-Identifier: Apache-2.0

import 'package:ten_project_cua_ban/features/player/infrastructure/command_source.dart';

final class RecordedPlayerCall {
  RecordedPlayerCall({
    required this.name,
    required Map<String, Object?> arguments,
    required this.source,
    required this.order,
    required this.callCount,
  }) : arguments = Map<String, Object?>.unmodifiable(arguments);

  final String name;
  final Map<String, Object?> arguments;
  final CommandSource? source;
  final int order;
  final int callCount;
}

/// Records handler/engine calls without coupling tests to a concrete engine.
final class PlayerCallRecorder {
  final List<RecordedPlayerCall> _calls = <RecordedPlayerCall>[];
  final Map<String, int> _callCounts = <String, int>{};

  List<RecordedPlayerCall> get calls =>
      List<RecordedPlayerCall>.unmodifiable(_calls);

  int callCountFor(String name) => _callCounts[name] ?? 0;

  RecordedPlayerCall record(
    String name, {
    Map<String, Object?> arguments = const <String, Object?>{},
    CommandSource? source,
  }) {
    final callCount = (_callCounts[name] ?? 0) + 1;
    final call = RecordedPlayerCall(
      name: name,
      arguments: arguments,
      source: source,
      order: _calls.length + 1,
      callCount: callCount,
    );
    _calls.add(call);
    _callCounts[name] = callCount;
    return call;
  }
}
