// Local runners:
//
// Android: flutter test integration_test/player_local_smoke_test.dart -d <device-id>
// iOS: flutter test integration_test/player_local_smoke_test.dart -d <device-id>
// macOS: flutter test integration_test/player_local_smoke_test.dart -d macos
// Web: flutter drive --driver=test_driver/integration_test.dart
//      --target=integration_test/player_local_smoke_test.dart -d chrome

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ten_project_cua_ban/main.dart' as app;

const _fixtureAsset = 'assets/test_audio/player_fixture_2s.wav';
const _fixtureSha256 =
    '7c0075e0719e58447341850c008eda6effe6f10eefdcd6952c63926378cc8ab2';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('player app boots on a local target', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('ViListen'), findsOneWidget);
  });

  testWidgets('local audio fixture is bundled with deterministic bytes', (
    tester,
  ) async {
    await tester.pump();

    final loaded = await rootBundle.load(_fixtureAsset);
    final bytes = loaded.buffer.asUint8List(
      loaded.offsetInBytes,
      loaded.lengthInBytes,
    );

    expect(bytes.length, 192044);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(sha256.convert(bytes).toString(), _fixtureSha256);
  });
}
