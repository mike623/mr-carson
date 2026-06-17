import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({
    required String title,
    String? body,
    IconData? icon,
  }) {
    return MaterialApp(
      theme: buildMrCarsonTheme(),
      home: Scaffold(
        body: EmptyState(title: title, body: body, icon: icon),
      ),
    );
  }

  testWidgets('renders title text', (tester) async {
    await tester.pumpWidget(buildSubject(
      title: 'Nothing to show just yet, sir.',
    ));
    await tester.pump();

    expect(find.text('Nothing to show just yet, sir.'), findsOneWidget);
  });

  testWidgets('renders optional body text when provided', (tester) async {
    await tester.pumpWidget(buildSubject(
      title: 'Nothing to show just yet, sir.',
      body: 'Add a receipt to get started.',
    ));
    await tester.pump();

    expect(find.text('Nothing to show just yet, sir.'), findsOneWidget);
    expect(find.text('Add a receipt to get started.'), findsOneWidget);
  });

  testWidgets('does not render body when not provided', (tester) async {
    await tester.pumpWidget(buildSubject(
      title: 'Nothing to show just yet, sir.',
    ));
    await tester.pump();

    // Only the title text should exist — no body widget
    expect(find.text('Nothing to show just yet, sir.'), findsOneWidget);
    final allTexts = tester.widgetList<Text>(find.byType(Text));
    expect(allTexts.length, 1);
  });

  testWidgets('renders icon when provided', (tester) async {
    await tester.pumpWidget(buildSubject(
      title: 'Nothing to show just yet, sir.',
      icon: Icons.receipt_long,
    ));
    await tester.pump();

    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
  });

  testWidgets('does not render icon when not provided', (tester) async {
    await tester.pumpWidget(buildSubject(
      title: 'Nothing to show just yet, sir.',
    ));
    await tester.pump();

    expect(find.byType(Icon), findsNothing);
  });
}
