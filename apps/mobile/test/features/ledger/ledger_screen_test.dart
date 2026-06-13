import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/features/ledger/ledger_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({
    List<LedgerPending> pending = const [],
    void Function(String)? onReviewPending,
  }) {
    return MaterialApp(
      theme: buildMrCarsonTheme(),
      home: LedgerScreen(
        pending: pending,
        onReviewPending: onReviewPending,
      ),
    );
  }

  testWidgets('renders header, donut total, and recent expense tiles',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('The Ledger'), findsOneWidget);
    expect(find.text('£1,284.60'), findsOneWidget);
    expect(find.text('Caffè Nero'), findsOneWidget);
    expect(find.text('The Wolseley'), findsOneWidget);
    expect(find.text('Waitrose'), findsOneWidget);
  });

  testWidgets('shows pending card with stage text and Review button',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(
        pending: const [
          LedgerPending(
            id: 'p1',
            ready: true,
            stage: 'Ready for your review',
            pct: 100,
            merchant: 'Caffè Nero',
            total: '£6.15',
          ),
        ],
        onReviewPending: (_) {},
      ),
    );
    await tester.pump();

    expect(find.text('Ready for your review'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
  });
}
