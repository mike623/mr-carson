import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/receipt_image_store.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/confirm/confirm_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

/// A no-op image store — avoids real `dart:io` file checks, which do not resolve
/// inside the fake-async test zone.
class _FakeImageStore extends ReceiptImageStore {
  final List<String> cleaned = [];

  @override
  Future<void> cleanup(String path) async {
    cleaned.add(path);
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ExpenseDraft sampleDraft() => const ExpenseDraft(
        merchant: 'Caffè Nero',
        date: '2026-06-12',
        currency: 'GBP',
        total: 6.15,
        items: [
          ExpenseItemDraft(name: 'Cappuccino', amount: 3.20, category: 'Dining'),
          ExpenseItemDraft(
              name: 'Almond Croissant', amount: 2.95, category: 'Dining'),
        ],
      );

  /// Inserts a pending row in [PendingStatus.awaitingConfirmation] with the
  /// given draft, returning its id.
  Future<String> seedAwaiting(ExpenseDraft draft) async {
    const id = 'pending-1';
    await db.into(db.pendingExpenses).insert(
          PendingExpensesCompanion.insert(
            id: id,
            status: PendingStatus.awaitingConfirmation.name,
            filePath: const Value('/tmp/does-not-exist.jpg'),
            extractedJson: Value(jsonEncode(draft.toJson())),
          ),
        );
    return id;
  }

  /// Unmounts the widget tree (disposing the ProviderScope and its drift watch
  /// subscription) and flushes the zero-duration timer drift schedules when it
  /// closes a stream — otherwise the framework reports a pending timer.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Widget buildSubject({
    required String pendingId,
    VoidCallback? onDone,
    VoidCallback? onDiscarded,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        receiptImageStoreProvider.overrideWithValue(_FakeImageStore()),
      ],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: ConfirmScreen(
          pendingId: pendingId,
          onDone: onDone ?? () {},
          onDiscarded: onDiscarded ?? () {},
        ),
      ),
    );
  }

  testWidgets('shows loading while the pending row has not streamed yet',
      (tester) async {
    // Override the source stream with one that never emits so the AsyncValue
    // stays in its loading state (and no real drift stream timer leaks).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          pendingReceiptsProvider.overrideWith(
            // A stream that never emits and never closes — keeps the
            // AsyncValue in its loading state.
            (ref) {
              final controller = StreamController<List<PendingExpense>>();
              ref.onDispose(controller.close);
              return controller.stream;
            },
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: ConfirmScreen(
            pendingId: 'pending-1',
            onDone: () {},
            onDiscarded: () {},
          ),
        ),
      ),
    );
    expect(find.byType(LoadingState), findsOneWidget);
  });

  testWidgets('renders the real draft from extractedJson', (tester) async {
    final id = await seedAwaiting(sampleDraft());
    await tester.pumpWidget(buildSubject(pendingId: id));
    await tester.pumpAndSettle();

    // Merchant + total + line items come from the draft, not hardcoded values.
    expect(find.text('Caffè Nero'), findsAtLeastNWidgets(1));
    expect(find.text('£6.15'), findsOneWidget);
    expect(find.text('Cappuccino'), findsOneWidget);
    expect(find.text('Almond Croissant'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('editing the merchant updates the displayed value',
      (tester) async {
    final id = await seedAwaiting(sampleDraft());
    await tester.pumpWidget(buildSubject(pendingId: id));
    await tester.pumpAndSettle();

    final merchantValueFinder = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('Caffè Nero'),
    );
    await tester.tap(merchantValueFinder.first);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Pret A Manger');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Pret A Manger'), findsAtLeastNWidgets(1));

    await disposeTree(tester);
  });

  testWidgets('Save commits the draft and inserts an expense', (tester) async {
    final id = await seedAwaiting(sampleDraft());
    var doneCalled = false;
    await tester.pumpWidget(
      buildSubject(pendingId: id, onDone: () => doneCalled = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(doneCalled, isTrue);

    // The expense was persisted and the pending row moved to inserted.
    final recents = await db.watchRecentExpenses().first;
    expect(recents, hasLength(1));
    expect(recents.first.merchant, 'Caffè Nero');
    expect(recents.first.total, 6.15);

    final pending = await (db.select(db.pendingExpenses)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(pending.status, PendingStatus.inserted.name);

    await disposeTree(tester);
  });

  testWidgets('Discard rejects the receipt without inserting an expense',
      (tester) async {
    final id = await seedAwaiting(sampleDraft());
    var discardedCalled = false;
    await tester.pumpWidget(
      buildSubject(pendingId: id, onDiscarded: () => discardedCalled = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    // The reject + image cleanup are real async (DB + filesystem); give the
    // continuation a chance to run before asserting the callback fired.
    final pending = await (db.select(db.pendingExpenses)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(pending.status, PendingStatus.rejected.name);

    final recents = await db.watchRecentExpenses().first;
    expect(recents, isEmpty);

    await tester.pumpAndSettle();
    expect(discardedCalled, isTrue);

    await disposeTree(tester);
  });
}
