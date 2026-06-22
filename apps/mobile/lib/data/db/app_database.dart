import 'dart:convert';
import 'dart:io';

// Hide drift's internal QueryRow — our domain QueryRow (ai_models.dart) wins.
// We only ever touch drift rows via `.data`, never by the QueryRow name.
import 'package:drift/drift.dart' hide QueryRow;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/date_range.dart';
import '../../domain/models/ai_models.dart';
import '../../domain/models/expense_detail.dart';
import '../../domain/models/expense_summary.dart';
import '../../domain/models/monthly_summary.dart';
import 'tables.dart';

part 'app_database.g.dart';

const _uuid = Uuid();

double _round2(num v) => (v * 100).round() / 100;

@DriftDatabase(
  tables: [Expenses, ExpenseItems, Categories, Merchants, PendingExpenses],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: expense-level categories (JSON array).
            await m.addColumn(expenses, expenses.categories);
          }
        },
      );

  // --- seed -----------------------------------------------------------------

  /// Ported from packages/database/src/seed.ts. Insert-or-ignore the taxonomy.
  Future<void> seedCategories() async {
    await batch((b) {
      b.insertAll(
        categories,
        kDefaultCategories
            .map((name) => CategoriesCompanion.insert(
                  name: name,
                  isDefault: const Value(true),
                ))
            .toList(),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  // --- writes ---------------------------------------------------------------

  /// Ported from expenses.ts `insertExpense`. Returns the new expense id.
  Future<String> insertExpense(
    ExpenseDraft expense, {
    String? sourceFile,
    String? imageHash,
  }) async {
    final id = _uuid.v4();
    // Expense-level tags: explicit list if given, else the distinct set of
    // line-item categories (insertion order preserved).
    final cats = (expense.categories != null && expense.categories!.isNotEmpty)
        ? expense.categories!
        : expense.items.map((i) => i.category).toSet().toList();
    await transaction(() async {
      await into(expenses).insert(ExpensesCompanion.insert(
        id: id,
        merchant: expense.merchant,
        date: expense.date,
        currency: expense.currency,
        total: expense.total,
        vat: Value(expense.vat ?? 0),
        categories: Value(cats.isEmpty ? null : jsonEncode(cats)),
        sourceFile: Value(sourceFile),
        imageHash: Value(imageHash),
      ));
      for (final item in expense.items) {
        await into(expenseItems).insert(ExpenseItemsCompanion.insert(
          id: _uuid.v4(),
          expenseId: id,
          name: item.name,
          category: item.category,
          amount: item.amount,
        ));
      }
      await into(merchants).insert(
        MerchantsCompanion.insert(
          name: expense.merchant,
          normalized: expense.merchant.trim().toLowerCase(),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
    return id;
  }

  /// Amends the expense-level fields of an existing expense. Line items are left
  /// untouched — the editor only changes merchant/total/date/categories (the
  /// design's edit screen keeps "the particulars as filed, sir"). Also records
  /// the (possibly new) merchant in the merchants table for autocomplete parity
  /// with [insertExpense].
  Future<void> updateExpense(
    String id, {
    required String merchant,
    required double total,
    required String date,
    required List<String> categories,
  }) async {
    final trimmed = merchant.trim();
    await transaction(() async {
      await (update(expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          merchant: Value(trimmed),
          total: Value(total),
          date: Value(date),
          categories:
              Value(categories.isEmpty ? null : jsonEncode(categories)),
        ),
      );
      await into(merchants).insert(
        MerchantsCompanion.insert(
          name: trimmed,
          normalized: trimmed.toLowerCase(),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Deletes an expense and its line items. Items are removed explicitly rather
  /// than relying on the FK cascade, since SQLite foreign-key enforcement is not
  /// guaranteed to be on for the native executor.
  Future<void> deleteExpense(String id) async {
    await transaction(() async {
      await (delete(expenseItems)..where((t) => t.expenseId.equals(id))).go();
      await (delete(expenses)..where((t) => t.id.equals(id))).go();
    });
  }

  // --- dedup ----------------------------------------------------------------

  /// Ported from `findByImageHash`.
  Future<String?> findByImageHash(String hash) async {
    final row = await (select(expenses)
          ..where((t) => t.imageHash.equals(hash))
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  /// Ported from `findSoftDuplicate` — same merchant (case-insensitive),
  /// date, total and currency.
  Future<SoftDuplicateMatch?> findSoftDuplicate({
    required String merchant,
    required String date,
    required double total,
    required String currency,
  }) async {
    final row = await (select(expenses)
          ..where((t) =>
              t.merchant.lower().equals(merchant.toLowerCase()) &
              t.date.equals(date) &
              t.total.equals(total) &
              t.currency.equals(currency))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return SoftDuplicateMatch(
        id: row.id, merchant: row.merchant, date: row.date, total: row.total);
  }

  // --- reads: queryExpenses -------------------------------------------------

  /// Faithful port of expenses.ts `queryExpenses`. Uses customSelect to mirror
  /// the dynamic where[]/params[] builder exactly — including the ORed
  /// `itemNames` synonym expansion that powers concept search.
  Future<QueryExpensesResult> queryExpenses(QueryExpensesArgs args) async {
    final where = <String>[];
    final vars = <Variable>[];

    if (args.category != null) {
      where.add('lower(i.category) = lower(?)');
      vars.add(Variable<String>(args.category!));
    }
    if (args.merchant != null) {
      where.add('lower(e.merchant) LIKE lower(?)');
      vars.add(Variable<String>('%${args.merchant}%'));
    }
    if (args.itemName != null) {
      where.add('lower(i.name) LIKE lower(?)');
      vars.add(Variable<String>('%${args.itemName}%'));
    }
    if (args.itemNames != null && args.itemNames!.isNotEmpty) {
      final clauses =
          args.itemNames!.map((_) => 'lower(i.name) LIKE lower(?)').join(' OR ');
      where.add('($clauses)');
      for (final n in args.itemNames!) {
        vars.add(Variable<String>('%$n%'));
      }
    }

    final range = resolveDateRange(args);
    if (range != null) {
      where.add('e.date >= ? AND e.date <= ?');
      vars.add(Variable<String>(range.start));
      vars.add(Variable<String>(range.end));
    }

    final whereSql = where.isEmpty ? '1 = 1' : where.join(' AND ');
    final limit = args.limit ?? 200;

    final rows = await customSelect(
      '''
      SELECT
        e.id          AS expense_id,
        e.date        AS date,
        e.merchant    AS merchant,
        i.name        AS name,
        i.category    AS category,
        i.amount      AS amount,
        e.currency    AS currency,
        e.source_file AS source_file
      FROM expenses e
      JOIN expense_items i ON i.expense_id = e.id
      WHERE $whereSql
      ORDER BY e.date DESC, e.merchant ASC
      LIMIT ?
      ''',
      variables: [...vars, Variable<int>(limit)],
      readsFrom: {expenses, expenseItems},
    ).get();

    final mapped = rows.map((r) {
      final d = r.data;
      return QueryRow(
        expenseId: d['expense_id'] as String,
        date: d['date'] as String,
        merchant: d['merchant'] as String,
        name: d['name'] as String,
        category: d['category'] as String,
        amount: (d['amount'] as num).toDouble(),
        currency: d['currency'] as String,
        sourceFile: d['source_file'] as String?,
      );
    }).toList();

    final total = _round2(mapped.fold<double>(0, (a, r) => a + r.amount));
    final currency = mapped.isNotEmpty ? mapped.first.currency : 'GBP';

    // VAT lives on expenses, not items — compute separately to avoid
    // double-counting across the joined line items.
    final vatWhere = <String>[];
    final vatVars = <Variable>[];
    if (args.category != null) {
      vatWhere.add(
          'EXISTS (SELECT 1 FROM expense_items i WHERE i.expense_id = e.id AND lower(i.category) = lower(?))');
      vatVars.add(Variable<String>(args.category!));
    }
    if (args.merchant != null) {
      vatWhere.add('lower(e.merchant) LIKE lower(?)');
      vatVars.add(Variable<String>('%${args.merchant}%'));
    }
    if (args.itemName != null) {
      vatWhere.add(
          'EXISTS (SELECT 1 FROM expense_items i WHERE i.expense_id = e.id AND lower(i.name) LIKE lower(?))');
      vatVars.add(Variable<String>('%${args.itemName}%'));
    }
    if (args.itemNames != null && args.itemNames!.isNotEmpty) {
      final clauses =
          args.itemNames!.map((_) => 'lower(i.name) LIKE lower(?)').join(' OR ');
      vatWhere.add(
          'EXISTS (SELECT 1 FROM expense_items i WHERE i.expense_id = e.id AND ($clauses))');
      for (final n in args.itemNames!) {
        vatVars.add(Variable<String>('%$n%'));
      }
    }
    if (range != null) {
      vatWhere.add('e.date >= ? AND e.date <= ?');
      vatVars.add(Variable<String>(range.start));
      vatVars.add(Variable<String>(range.end));
    }
    final vatWhereSql = vatWhere.isEmpty ? '1 = 1' : vatWhere.join(' AND ');
    final vatRow = await customSelect(
      'SELECT COALESCE(SUM(vat), 0) AS vat_total FROM expenses e WHERE $vatWhereSql',
      variables: vatVars,
      readsFrom: {expenses, expenseItems},
    ).getSingle();
    final vatTotal = _round2((vatRow.data['vat_total'] as num).toDouble());

    return QueryExpensesResult(
      total: total,
      vatTotal: vatTotal,
      currency: currency,
      count: mapped.length,
      rows: mapped,
    );
  }

  // --- reads: chart data ----------------------------------------------------

  /// Ported from `byCategoryOverTime`. NOTE: DuckDB's DATE_TRUNC has no SQLite
  /// equivalent, so buckets are formed with substr/strftime over the
  /// 'YYYY-MM-DD' date text:
  ///   day   -> 'YYYY-MM-DD'  month -> 'YYYY-MM'  week -> ISO 'YYYY-WW'
  Future<({List<CategoryBucket> rows, Granularity granularity, String currency})>
      byCategoryOverTime(QueryExpensesArgs args,
          {Granularity granularity = Granularity.week}) async {
    final bucketExpr = switch (granularity) {
      Granularity.day => "substr(e.date, 1, 10)",
      Granularity.month => "substr(e.date, 1, 7)",
      Granularity.week => "strftime('%Y-%W', e.date)",
    };

    final where = <String>[];
    final vars = <Variable>[];
    if (args.category != null) {
      where.add('lower(i.category) = lower(?)');
      vars.add(Variable<String>(args.category!));
    }
    final range = resolveDateRange(
      args.dateRange == null && args.startDate == null
          ? args.copyWith(dateRange: DateRange.lastMonth)
          : args,
    );
    if (range != null) {
      where.add('e.date >= ? AND e.date <= ?');
      vars.add(Variable<String>(range.start));
      vars.add(Variable<String>(range.end));
    }
    final whereSql = where.isEmpty ? '1 = 1' : where.join(' AND ');

    final raw = await customSelect(
      '''
      SELECT
        $bucketExpr AS bucket,
        i.category  AS category,
        SUM(i.amount) AS total,
        MAX(e.currency) AS currency
      FROM expenses e
      JOIN expense_items i ON i.expense_id = e.id
      WHERE $whereSql
      GROUP BY bucket, i.category
      ORDER BY bucket ASC, total DESC
      ''',
      variables: vars,
      readsFrom: {expenses, expenseItems},
    ).get();

    final rows = raw
        .map((r) => CategoryBucket(
              bucket: r.data['bucket'] as String,
              category: r.data['category'] as String,
              total: _round2((r.data['total'] as num).toDouble()),
            ))
        .toList();
    final currency =
        raw.isNotEmpty ? (raw.first.data['currency'] as String) : 'GBP';
    return (rows: rows, granularity: granularity, currency: currency);
  }

  // --- reactive watches -------------------------------------------------------

  Stream<List<ExpenseSummary>> watchRecentExpenses({int limit = 50}) {
    return customSelect(
      '''
      SELECT
        e.id       AS id,
        e.merchant AS merchant,
        -- Display category is the user-editable expense-level tag (first of the
        -- categories JSON array). Falls back to the dominant line-item category
        -- for legacy rows that predate expense-level categories.
        COALESCE(
          json_extract(e.categories, '\$[0]'),
          (SELECT i.category FROM expense_items i
           WHERE i.expense_id = e.id
           ORDER BY i.amount DESC LIMIT 1),
          'Other') AS category,
        e.total    AS total,
        e.currency AS currency,
        e.date     AS date
      FROM expenses e
      ORDER BY e.date DESC, e.created_at DESC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {expenses, expenseItems},
    ).watch().map((rows) => rows.map((r) {
          final d = r.data;
          return ExpenseSummary(
            id: d['id'] as String,
            merchant: d['merchant'] as String,
            category: d['category'] as String,
            total: (d['total'] as num).toDouble(),
            currency: d['currency'] as String,
            date: d['date'] as String,
          );
        }).toList());
  }

  Stream<MonthlySummary> watchMonthlySummary(DateTime month) {
    final monthStr =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final startDate = '$monthStr-01';
    // Half-open range: e.date >= startDate AND e.date < nextMonthFirst
    // avoids DST-driven off-by-one from subtracting Duration(days:1).
    final nextMonth = month.month == 12
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);
    final nextMonthStr = [
      nextMonth.year,
      nextMonth.month.toString().padLeft(2, '0'),
      nextMonth.day.toString().padLeft(2, '0'),
    ].join('-');

    // Group by the user-editable expense-level category (first tag) and sum the
    // expense total, so the donut matches the ledger list and detail view.
    // ponytail: a multi-category expense counts wholly under its primary
    // category — we don't store per-category amounts to split it. Add a split
    // here once line items carry the edited categories.
    return customSelect(
      '''
      SELECT
        COALESCE(
          json_extract(e.categories, '\$[0]'),
          (SELECT i.category FROM expense_items i
           WHERE i.expense_id = e.id
           ORDER BY i.amount DESC LIMIT 1),
          'Other')               AS category,
        SUM(e.total)             AS category_total,
        MAX(e.currency)          AS currency
      FROM expenses e
      WHERE e.date >= ? AND e.date < ?
      GROUP BY category
      ORDER BY category_total DESC
      ''',
      variables: [Variable<String>(startDate), Variable<String>(nextMonthStr)],
      readsFrom: {expenses, expenseItems},
    ).watch().map((rows) {
      if (rows.isEmpty) {
        return MonthlySummary(
            month: monthStr, total: 0, currency: 'GBP', buckets: []);
      }
      double total = 0;
      final buckets = <CategoryBucket>[];
      for (final r in rows) {
        final t = (r.data['category_total'] as num).toDouble();
        total += t;
        buckets.add(CategoryBucket(
          bucket: monthStr,
          category: r.data['category'] as String,
          total: _round2(t),
        ));
      }
      return MonthlySummary(
        month: monthStr,
        total: _round2(total),
        currency: rows.first.data['currency'] as String,
        buckets: buckets,
      );
    });
  }

  Stream<ExpenseDetail?> watchExpenseById(String id) {
    return customSelect(
      '''
      SELECT
        e.id          AS e_id,
        e.merchant    AS merchant,
        e.categories  AS categories,
        e.date        AS date,
        e.total       AS total,
        e.currency    AS currency,
        e.source_file AS source_file,
        i.id          AS i_id,
        i.name        AS i_name,
        i.category    AS i_category,
        i.amount      AS i_amount
      FROM expenses e
      LEFT JOIN expense_items i ON i.expense_id = e.id
      WHERE e.id = ?
      ORDER BY i.amount DESC
      ''',
      variables: [Variable<String>(id)],
      readsFrom: {expenses, expenseItems},
    ).watch().map((rows) {
      if (rows.isEmpty) return null;
      final first = rows.first.data;
      final items = rows
          .where((r) => r.data['i_id'] != null)
          .map((r) => ExpenseItemSummary(
                id: r.data['i_id'] as String,
                name: r.data['i_name'] as String,
                category: r.data['i_category'] as String,
                amount: (r.data['i_amount'] as num).toDouble(),
              ))
          .toList();
      // Expense-level tags: stored JSON array, else fall back to the distinct
      // line-item categories, else 'Other'.
      List<String> cats;
      final rawCats = first['categories'] as String?;
      if (rawCats != null && rawCats.isNotEmpty) {
        cats = (jsonDecode(rawCats) as List).cast<String>();
      } else {
        cats = items.map((i) => i.category).toSet().toList();
      }
      if (cats.isEmpty) cats = const ['Other'];
      return ExpenseDetail(
        id: first['e_id'] as String,
        merchant: first['merchant'] as String,
        categories: cats,
        date: first['date'] as String,
        total: (first['total'] as num).toDouble(),
        currency: first['currency'] as String,
        sourceFile: first['source_file'] as String?,
        items: items,
      );
    });
  }

  /// Ported from `topMerchants`.
  Future<List<({String merchant, double total, String currency})>> topMerchants(
    QueryExpensesArgs args, {
    int topN = 5,
  }) async {
    final where = <String>[];
    final vars = <Variable>[];
    final range = resolveDateRange(args);
    if (range != null) {
      where.add('date >= ? AND date <= ?');
      vars.add(Variable<String>(range.start));
      vars.add(Variable<String>(range.end));
    }
    final whereSql = where.isEmpty ? '1 = 1' : where.join(' AND ');

    final rows = await customSelect(
      '''
      SELECT merchant, SUM(total) AS total, MAX(currency) AS currency
      FROM expenses
      WHERE $whereSql
      GROUP BY merchant
      ORDER BY total DESC
      LIMIT ?
      ''',
      variables: [...vars, Variable<int>(topN)],
      readsFrom: {expenses},
    ).get();

    return rows
        .map((r) => (
              merchant: r.data['merchant'] as String,
              total: (r.data['total'] as num).toDouble(),
              currency: r.data['currency'] as String,
            ))
        .toList();
  }
}

/// Lightweight projection used by [AppDatabase.findSoftDuplicate].
/// Named to avoid colliding with drift's generated `Expense` row class.
class SoftDuplicateMatch {
  final String id;
  final String merchant;
  final String date;
  final double total;
  const SoftDuplicateMatch({
    required this.id,
    required this.merchant,
    required this.date,
    required this.total,
  });
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mr_carson.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
