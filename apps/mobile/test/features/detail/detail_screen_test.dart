import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/domain/models/expense_detail.dart';
import 'package:mr_carson/features/detail/detail_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _wrap({
  required AppDatabase db,
  required String expenseId,
  VoidCallback? onBack,
}) {
  final repo = ExpenseRepository(db);
  final pendingRepo = PendingRepository(db);

  return ProviderScope(
    overrides: [
      expenseRepositoryProvider.overrideWithValue(repo),
      pendingRepositoryProvider.overrideWithValue(pendingRepo),
    ],
    child: MaterialApp(
      theme: buildMrCarsonTheme(),
      home: DetailScreen(
        id: expenseId,
        onBack: onBack ?? () {},
      ),
    ),
  );
}

/// Replace the widget tree with an empty container to flush Drift's
/// zero-duration stream-cleanup timers before the test ends.
/// Must be called at the END of each testWidgets body that uses a real DB.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ── loading state ──────────────────────────────────────────────────────────

  testWidgets('shows loading indicator while provider resolves', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'loading-id', onBack: () {}),
        ),
      ),
    );

    // First frame — provider has not emitted yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // ── null / not found ───────────────────────────────────────────────────────

  testWidgets('shows not-found state for unknown id', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    await tester.pumpWidget(_wrap(db: db, expenseId: 'no-such-id'));
    await tester.pump();
    await tester.pump();

    // Should not crash; should show an empty / not-found message.
    expect(find.text('The Wolseley'), findsNothing);
    expect(find.textContaining('Nothing found'), findsOneWidget);

    await _drain(tester);
  });

  // ── error state ────────────────────────────────────────────────────────────

  testWidgets('shows error state when provider errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => Stream.error(Exception('disk failure')),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'any', onBack: () {}),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
  });

  // ── happy path: merchant + line items ─────────────────────────────────────

  testWidgets('renders merchant name and line items from DB', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'The Wolseley',
        date: '2026-06-11',
        currency: 'GBP',
        total: 84.09,
        items: [
          ExpenseItemDraft(name: 'Eggs Royale', amount: 15.75, category: 'Dining'),
          ExpenseItemDraft(name: "Buck's Fizz", amount: 24.00, category: 'Dining'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(db: db, expenseId: id));
    await tester.pump();
    await tester.pump();

    // Merchant name rendered
    expect(find.text('The Wolseley'), findsOneWidget);

    // Line items rendered
    expect(find.text('Eggs Royale'), findsOneWidget);
    expect(find.textContaining("Buck's Fizz"), findsOneWidget);

    // NO hardcoded stub data from old screen
    expect(find.text('Full English'), findsNothing);
    expect(find.text('Pastry basket'), findsNothing);

    await _drain(tester);
  });

  // ── total is displayed ────────────────────────────────────────────────────

  testWidgets('renders total amount', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Pret',
        date: '2026-06-10',
        currency: 'GBP',
        total: 7.50,
        items: [
          ExpenseItemDraft(name: 'Sandwich', amount: 7.50, category: 'Dining'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(db: db, expenseId: id));
    await tester.pump();
    await tester.pump();

    expect(find.text('Pret'), findsOneWidget);
    expect(find.textContaining('7.50'), findsAny);

    await _drain(tester);
  });

  // ── receipt image (F1) ────────────────────────────────────────────────────

  testWidgets('renders Image.file when sourceFile is a valid temp path',
      (tester) async {
    // Write a minimal 1×1 PNG so Image.file can actually decode it.
    final tmpDir = Directory.systemTemp.createTempSync('mr_carson_test_');
    final tmpFile = File('${tmpDir.path}/receipt.png');
    // Minimal valid 1×1 transparent PNG (67 bytes).
    tmpFile.writeAsBytesSync([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1×1
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // bit depth/color
      0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, // IDAT length + type
      0x54, 0x08, 0xd7, 0x63, 0xf8, 0xcf, 0xc0, 0x00, // IDAT data
      0x00, 0x00, 0x02, 0x00, 0x01, 0xe2, 0x21, 0xbc, // IDAT data cont.
      0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, // IEND length + type
      0x44, 0xae, 0x42, 0x60, 0x82,                   // IEND data
    ]);
    addTearDown(() => tmpDir.deleteSync(recursive: true));

    final detail = ExpenseDetail(
      id: 'img-test',
      merchant: 'The Savoy',
      categories: ['Dining'],
      date: '2026-06-17',
      total: 42.00,
      currency: 'GBP',
      sourceFile: tmpFile.path,
      items: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => Stream.value(detail),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'img-test', onBack: () {}),
        ),
      ),
    );
    await tester.pump(); // let stream emit
    await tester.pump(); // let image widget settle

    // An Image widget must be present (Image.file) and no EmptyState placeholder.
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    // The Image widget is backed by a FileImage, not an AssetBundleImageProvider.
    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isA<FileImage>());
  });

  testWidgets('renders placeholder when sourceFile is null', (tester) async {
    const detail = ExpenseDetail(
      id: 'no-img',
      merchant: 'Claridges',
      categories: ['Dining'],
      date: '2026-06-17',
      total: 55.00,
      currency: 'GBP',
      sourceFile: null,
      items: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => Stream.value(detail),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'no-img', onBack: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // No Image widget — only the striped placeholder is shown.
    expect(find.byType(Image), findsNothing);
    expect(find.text('RECEIPT PHOTO'), findsOneWidget);
  });

  testWidgets(
      'uses Image.file (not Image.asset) for a non-null sourceFile path',
      (tester) async {
    // This test verifies that _ReceiptImage uses Image.file regardless of
    // whether the file exists — the errorBuilder handles missing files at
    // runtime. What matters in the widget test is that the provider is
    // FileImage (not an AssetBundleImageProvider).
    const detail = ExpenseDetail(
      id: 'bad-path',
      merchant: 'Ritz',
      categories: ['Dining'],
      date: '2026-06-17',
      total: 99.00,
      currency: 'GBP',
      sourceFile: '/tmp/mr_carson_nonexistent_receipt_12345.png',
      items: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => Stream.value(detail),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'bad-path', onBack: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // An Image widget is rendered (Image.file), backed by FileImage.
    // The errorBuilder will eventually show 'RECEIPT PHOTO' at runtime when
    // the file cannot be loaded, but in the test VM image loading is
    // deferred; we assert the provider type instead.
    expect(find.byType(Image), findsOneWidget);
    final imageWidget = tester.widget<Image>(find.byType(Image));
    expect(imageWidget.image, isA<FileImage>());
  });

  // ── back callback ─────────────────────────────────────────────────────────

  testWidgets('onBack is called when back button is tapped', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Costa',
        date: '2026-06-01',
        currency: 'GBP',
        total: 3.50,
        items: [
          ExpenseItemDraft(name: 'Coffee', amount: 3.50, category: 'Dining'),
        ],
      ),
    );

    bool backed = false;
    await tester.pumpWidget(_wrap(db: db, expenseId: id, onBack: () => backed = true));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    expect(backed, isTrue);

    await _drain(tester);
  });
}
