import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: buildMrCarsonTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('LoadingState shows spinner and optional label', (tester) async {
    await tester.pumpWidget(wrap(const LoadingState(label: 'Reading the ledger')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Reading the ledger'), findsOneWidget);
  });

  testWidgets('ErrorRetryState shows message and fires onRetry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      wrap(
        ErrorRetryState(
          title: 'Something went wrong',
          message: 'The model failed to load.',
          onRetry: () => retried++,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('The model failed to load.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('EmptyState shows icon, title, and subtitle', (tester) async {
    await tester.pumpWidget(
      wrap(
        const EmptyState(
          icon: Icons.receipt_long,
          title: 'No expenses yet',
          subtitle: 'Send Mr. Carson a receipt to begin.',
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    expect(find.text('No expenses yet'), findsOneWidget);
    expect(find.text('Send Mr. Carson a receipt to begin.'), findsOneWidget);
  });
}
