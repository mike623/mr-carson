import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({String? message}) {
    return MaterialApp(
      theme: buildMrCarsonTheme(),
      home: Scaffold(
        body: LoadingState(message: message),
      ),
    );
  }

  testWidgets('renders brass spinner without message', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders spinner with optional caption', (tester) async {
    await tester.pumpWidget(buildSubject(message: 'Loading your ledger…'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading your ledger…'), findsOneWidget);
  });

  testWidgets('widget is centered on screen', (tester) async {
    await tester.pumpWidget(buildSubject(message: 'One moment, sir.'));
    await tester.pump();

    final center = find.byType(Center);
    expect(center, findsWidgets);
  });
}
