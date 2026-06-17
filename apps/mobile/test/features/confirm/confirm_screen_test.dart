import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/ai/receipt_pipeline.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/confirm/confirm_screen.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';
import 'package:mr_carson/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late AppDatabase db;
  late PendingRepository pendingRepo;
  late String pendingId;

  const stubDraft = ExpenseDraft(
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    pendingRepo = PendingRepository(db);
    pendingId = await pendingRepo.create(filePath: '/fake/receipt.jpg');
    await pendingRepo.setStatus(
      pendingId,
      PendingStatus.awaitingConfirmation,
      extractedJson: jsonEncode(stubDraft.toJson()),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildSubject(String id, {List<Override> extraOverrides = const []}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        pendingRepositoryProvider.overrideWithValue(pendingRepo),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: ConfirmScreen(pendingId: id),
      ),
    );
  }

  testWidgets('renders real draft — merchant and total from DB', (tester) async {
    await tester.pumpWidget(buildSubject(pendingId));
    await tester.pumpAndSettle();

    expect(find.text('Caffè Nero'), findsAtLeastNWidgets(1));
    expect(find.text('GBP 6.15'), findsOneWidget);
  });

  testWidgets('renders line items from real draft', (tester) async {
    await tester.pumpWidget(buildSubject(pendingId));
    await tester.pumpAndSettle();

    expect(find.text('Cappuccino'), findsOneWidget);
    expect(find.text('Almond Croissant'), findsOneWidget);
  });

  testWidgets('editing merchant updates the displayed name', (tester) async {
    await tester.pumpWidget(buildSubject(pendingId));
    await tester.pumpAndSettle();

    // Tap the merchant GestureDetector to enter edit mode.
    final merchantFinder = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('Caffè Nero'),
    );
    await tester.tap(merchantFinder.first);
    await tester.pump();

    expect(find.byType(TextField), findsAtLeastNWidgets(1));
    await tester.enterText(find.byType(TextField).first, 'Pret A Manger');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Pret A Manger'), findsAtLeastNWidgets(1));
  });

  testWidgets('tapping Save expense calls commitConfirmed via pipeline',
      (tester) async {
    String? committedMerchant;
    double? committedTotal;

    final fakePipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      onCommit: (id, draft) {
        committedMerchant = draft.merchant;
        committedTotal = draft.total;
      },
      onReject: (_) {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          pendingRepositoryProvider.overrideWithValue(pendingRepo),
          receiptPipelineProvider.overrideWithValue(fakePipeline),
          shellViewModelProvider.overrideWith(() => _NoNavShellViewModel()),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: ConfirmScreen(pendingId: pendingId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(committedMerchant, equals('Caffè Nero'));
    expect(committedTotal, equals(6.15));
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A fake [ReceiptPipelineService] subclass that captures commit/reject calls
/// without touching the real Gemma service or database.
///
/// We subclass (not implement) because [ReceiptPipelineService] is concrete.
/// The parent constructor requires [GemmaService], [AppDatabase], and
/// [PendingRepository] — we pass null-casted stubs because the overridden
/// methods never call super and the private fields are never read.
class _FakePipeline extends ReceiptPipelineService {
  _FakePipeline({
    required AppDatabase db,
    required PendingRepository repo,
    required this.onCommit,
    required this.onReject,
  }) : super(
          // GemmaService has a no-arg constructor; it is never called because
          // all public methods are overridden in this subclass.
          GemmaService(),
          db,
          repo,
        );

  final void Function(String pendingId, ExpenseDraft draft) onCommit;
  final void Function(String pendingId) onReject;

  @override
  Future<String> commitConfirmed(String pendingId, ExpenseDraft draft) async {
    onCommit(pendingId, draft);
    return 'fake-expense-id';
  }

  @override
  Future<void> reject(String pendingId) async {
    onReject(pendingId);
  }

  @override
  Future<ReceiptResult> processReceipt(String imagePath) async {
    return ReceiptResult.failure('fake-id', 'not used in test');
  }
}

/// A [ShellViewModel] subclass that suppresses navigation so widget tests
/// do not crash when saveConfirm/discardConfirm try to transition screens.
class _NoNavShellViewModel extends ShellViewModel {
  @override
  Future<void> saveConfirm(String pendingId, ExpenseDraft draft) async {
    await ref.read(receiptPipelineProvider).commitConfirmed(pendingId, draft);
  }

  @override
  Future<void> discardConfirm(String pendingId) async {
    await ref.read(receiptPipelineProvider).reject(pendingId);
  }
}
