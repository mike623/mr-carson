import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

class _NullGemma extends GemmaService {
  @override
  GemmaState get state => GemmaState.ready;
}

void main() {
  late AppDatabase db;
  late PendingRepository pending;
  late ChatService chat;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    pending = PendingRepository(db);
    chat = ChatService(_NullGemma(), db, pending);
  });
  tearDown(() => db.close());

  test('confident add (merchant + total) inserts an expense directly', () async {
    final out = await chat.runToolDebug('addExpense', {
      'merchant': 'Wagamama',
      'total': 12.0,
      'category': 'Dining',
      'date': 'yesterday',
    });

    expect(out.response['saved'], isTrue);
    expect(out.draftPendingId, isNull);

    // The expense is now queryable.
    final result = await db.queryExpenses(const QueryExpensesArgs());
    expect(result.count, 1);
    expect(result.rows.single.merchant, 'Wagamama');
  });

  test('low-confidence add (no total) writes an awaitingConfirmation pending row', () async {
    final out = await chat.runToolDebug('addExpense', {
      'merchant': 'Wagamama',
      // no total
    });

    expect(out.response['needsReview'], isTrue);
    expect(out.draftPendingId, isNotNull);

    // No expense was inserted.
    final result = await db.queryExpenses(const QueryExpensesArgs());
    expect(result.count, 0);

    // The pending row exists, awaiting confirmation, with the draft JSON.
    final row = await pending.getById(out.draftPendingId!);
    expect(row, isNotNull);
    expect(row!.status, PendingStatus.awaitingConfirmation.name);
    expect(row.filePath, isNull);
    expect(row.extractedJson, contains('Wagamama'));
  });

  test('low-confidence add (empty merchant) routes to review even with a total', () async {
    final out = await chat.runToolDebug('addExpense', {
      'merchant': '',
      'total': 5.0,
    });
    expect(out.response['needsReview'], isTrue);
    expect(out.draftPendingId, isNotNull);
  });
}
