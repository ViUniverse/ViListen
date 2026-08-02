// Local runners:
//
// Android: flutter test integration_test/player_local_smoke_test.dart -d <device-id>
// iOS: flutter test integration_test/player_local_smoke_test.dart -d <device-id>
// macOS: flutter test integration_test/player_local_smoke_test.dart -d macos
// Web: flutter drive --driver=test_driver/integration_test.dart
//      --target=integration_test/player_local_smoke_test.dart -d chrome

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ten_project_cua_ban/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('player app boots on a local target', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('ViListen'), findsOneWidget);
  });
}
