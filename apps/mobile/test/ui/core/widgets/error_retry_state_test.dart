import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({
    required String message,
    required VoidCallback onRetry,
  }) {
    return MaterialApp(
      theme: buildMrCarsonTheme(),
      home: Scaffold(
        body: ErrorRetryState(message: message, onRetry: onRetry),
      ),
    );
  }

  testWidgets('renders error message text', (tester) async {
    await tester.pumpWidget(buildSubject(
      message: 'Something went amiss, sir.',
      onRetry: () {},
    ));
    await tester.pump();

    expect(find.text('Something went amiss, sir.'), findsOneWidget);
  });

  testWidgets('renders Try again button', (tester) async {
    await tester.pumpWidget(buildSubject(
      message: 'Something went amiss, sir.',
      onRetry: () {},
    ));
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('invokes onRetry when Try again is tapped', (tester) async {
    var retried = false;
    await tester.pumpWidget(buildSubject(
      message: 'Something went amiss, sir.',
      onRetry: () => retried = true,
    ));
    await tester.pump();

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(retried, isTrue);
  });
}
