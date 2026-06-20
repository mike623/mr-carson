// Driver for `flutter drive` integration tests.
//
// Persists screenshots taken via `binding.takeScreenshot(<name>)` to
// build/e2e_screenshots/<name>.png. Run with:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/receipt_e2e_test.dart \
//     -d <device-id> --profile
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final dir = Directory('build/e2e_screenshots')
        ..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes);
      return true;
    },
  );
}
