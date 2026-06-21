import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error_reporter.dart';
import '../data/db/app_database.dart';
import '../data/providers.dart';
import '../data/repositories/pending_repository.dart';
import '../domain/models/ai_models.dart';
import 'receipt_ocr_engine.dart';
import 'prompts.dart';

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// The outcome of [ReceiptPipelineService.processReceipt].
///
/// On success, [draft] holds the extracted [ExpenseDraft] ready for the user
/// to review. On failure, [error] describes what went wrong.
///
/// In both cases [pendingId] identifies the row in `pending_expenses` that
/// tracks the lifecycle state.
class ReceiptResult {
  const ReceiptResult._({
    required this.ok,
    required this.pendingId,
    this.draft,
    this.error,
  });

  /// Successful extraction — [draft] is non-null.
  factory ReceiptResult.success(String pendingId, ExpenseDraft draft) =>
      ReceiptResult._(ok: true, pendingId: pendingId, draft: draft);

  /// Failed extraction — [error] describes the cause.
  factory ReceiptResult.failure(String pendingId, String error) =>
      ReceiptResult._(ok: false, pendingId: pendingId, error: error);

  final bool ok;
  final String pendingId;
  final ExpenseDraft? draft;
  final String? error;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Orchestrates the on-device receipt OCR + extraction pipeline.
///
/// Call sequence:
/// 1. [processReceipt] — runs the vision model, returns a [ReceiptResult].
///    The pending row is left in [PendingStatus.awaitingConfirmation] on
///    success, or [PendingStatus.failed] on error.
/// 2. UI shows a preview from [ReceiptResult.draft].
/// 3. [commitConfirmed] — user approves; row is inserted into `expenses`.
/// 4. [reject]          — user declines; row is marked rejected.
class ReceiptPipelineService {
  ReceiptPipelineService(this._engine, this._db, this._pending);

  final ReceiptOcrEngine _engine;
  final AppDatabase _db;
  final PendingRepository _pending;

  // --- public API -----------------------------------------------------------

  /// Runs OCR + structured extraction on the receipt at [imagePath].
  ///
  /// Never throws; all failures are captured in [ReceiptResult.failure] and
  /// the pending row is updated to [PendingStatus.failed].
  Future<ReceiptResult> processReceipt(String imagePath) async {
    final pendingId = await _pending.create(filePath: imagePath);
    return _runOcr(pendingId, imagePath);
  }

  /// Re-runs OCR on an already-failed pending row, reusing its stored image —
  /// the user need not upload again. The row's file path and id are preserved.
  Future<ReceiptResult> retry(String pendingId) async {
    final row = await _pending.getById(pendingId);
    final path = row?.filePath;
    if (path == null) {
      const msg = 'No image on file to retry.';
      await _pending.setStatus(pendingId, PendingStatus.failed,
          errorMessage: msg);
      return ReceiptResult.failure(pendingId, msg);
    }
    // Clear the prior error and re-enter the active state before retrying.
    await _pending.setStatus(pendingId, PendingStatus.received,
        errorMessage: '');
    return _runOcr(pendingId, path);
  }

  /// Core OCR pass against an existing pending row [pendingId].
  Future<ReceiptResult> _runOcr(String pendingId, String imagePath) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();

      final today = _todayIso();
      final prompt = '$kReceiptExtractionSystem\n\n'
          '${receiptExtractionPrompt(
        allowedCategories: kDefaultCategories,
        defaultCurrency: kDefaultCurrency,
        today: today,
      )}';

      final rawResponse =
          await _engine.readReceipt(prompt: prompt, imageBytes: imageBytes);

      // Debug builds: dump the model's raw output so key/format drift is
      // visible in the console (Xcode/`flutter logs`). Also kept in the DB row's
      // rawOcr column for post-hoc inspection.
      if (kDebugMode) {
        debugPrint('[receipt_ocr] raw response:\n$rawResponse');
      }

      // Strip optional markdown fences (```json ... ``` or ``` ... ```)
      final cleaned = _stripMarkdownFences(rawResponse);
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException(
          'Model returned ${decoded.runtimeType}, expected a JSON object',
        );
      }
      // Coerce missing/null required fields to safe defaults before parsing.
      // The model often omits a merchant or returns null total; without this the
      // strict freezed fromJson throws "type 'Null' is not a subtype of String"
      // and a salvageable receipt is lost. The user edits the rest in Confirm.
      final draft = ExpenseDraft.fromJson(coerceDraftJson(decoded, today));

      await _pending.setStatus(
        pendingId,
        PendingStatus.awaitingConfirmation,
        rawOcr: rawResponse,
        extractedJson: jsonEncode(draft.toJson()),
      );

      return ReceiptResult.success(pendingId, draft);
    } catch (e, st) {
      await reportError(e, st, hint: 'receipt_ocr');
      await _pending.setStatus(
        pendingId,
        PendingStatus.failed,
        errorMessage: e.toString(),
      );
      return ReceiptResult.failure(pendingId, e.toString());
    }
  }

  /// Persists a confirmed [ExpenseDraft] into the expense ledger.
  ///
  /// Returns the new expense ID. The pending row is moved to
  /// [PendingStatus.inserted].
  Future<String> commitConfirmed(
    String pendingId,
    ExpenseDraft draft,
  ) async {
    final pending = await _pending.getById(pendingId);
    if (pending == null ||
        pending.status != PendingStatus.awaitingConfirmation.name) {
      throw StateError(
        'commitConfirmed: pending receipt $pendingId is not in '
        'awaitingConfirmation state (status: ${pending?.status ?? "not found"})',
      );
    }
    final id = await _db.insertExpense(
      draft,
      sourceFile: pending.filePath,
      imageHash: await _hashOf(pending.filePath),
    );
    await _pending.setStatus(pendingId, PendingStatus.inserted);
    return id;
  }

  /// Marks a pending receipt as rejected by the user.
  Future<void> reject(String pendingId) async {
    await _pending.setStatus(pendingId, PendingStatus.rejected);
  }

  // --- helpers --------------------------------------------------------------

  /// SHA-256 of the file at [path], or null if absent/unreadable. Used to stamp
  /// committed expenses for duplicate detection (matches the hash computed by
  /// ReceiptImageStore.copyReceipt at upload).
  Future<String?> _hashOf(String? path) async {
    if (path == null) return null;
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return sha256.convert(await f.readAsBytes()).toString();
    } catch (_) {
      return null;
    }
  }

  /// Returns today's date as 'YYYY-MM-DD'.
  String _todayIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Normalises a raw model JSON object into a shape [ExpenseDraft.fromJson]
  /// can parse without throwing on null/missing required fields.
  ///
  /// Also tolerates *key drift*: small on-device models don't reliably emit the
  /// exact schema keys, so each field is read from a list of aliases (e.g. a
  /// line item's amount may arrive as `amount`, `price`, `cost`, or `value`).
  /// Without this, well-extracted receipts render as "Item / 0.00" placeholders.
  @visibleForTesting
  static Map<String, dynamic> coerceDraftJson(
    Map<String, dynamic> d,
    String today,
  ) {
    return {
      'merchant': _str(
          _pick(d, const ['merchant', 'store', 'vendor', 'seller', 'name']),
          'Unknown merchant'),
      'date': _str(_pick(d, const ['date', 'purchase_date', 'transaction_date']),
          today),
      'currency': _currency(
          _pick(d, const ['currency', 'currency_code', 'iso_currency'])),
      'total': _num(_pick(d, const [
        'total',
        'grand_total',
        'amount',
        'amount_due',
        'total_amount',
      ])),
      'vat': _numOrNull(_pick(d, const ['vat', 'tax', 'gst', 'sales_tax'])),
      'items': _items(_pick(d, const ['items', 'line_items', 'lineItems'])),
    };
  }

  // --- coercion helpers ---

  /// Returns the first non-null value among [keys] in [m].
  static Object? _pick(Map m, List<String> keys) {
    for (final k in keys) {
      if (m[k] != null) return m[k];
    }
    return null;
  }

  static String _str(Object? v, String fallback) =>
      (v is String && v.trim().isNotEmpty) ? v.trim() : fallback;

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    // Strip currency symbols / thousands separators: "£1,234.50" -> 1234.50
    final cleaned = '$v'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  static double? _numOrNull(Object? v) => v == null ? null : _num(v);

  /// DB enforces a 3-char currency; fall back to the default for null/junk.
  static String _currency(Object? v) {
    final cur = _str(v, kDefaultCurrency).toUpperCase();
    return cur.length == 3 ? cur : kDefaultCurrency;
  }

  static List<Map<String, dynamic>> _items(Object? raw) {
    final list = raw is List ? raw : const [];
    return list.whereType<Map>().map((it) {
      return <String, dynamic>{
        'name': _str(
            _pick(it, const ['name', 'title', 'description', 'item', 'desc']),
            'Item'),
        'amount': _num(_pick(
            it, const ['amount', 'price', 'cost', 'value', 'total', 'line_total'])),
        'category': _str(_pick(it, const ['category', 'type']), 'Other'),
      };
    }).toList();
  }

  /// Removes leading/trailing markdown code fences if present.
  String _stripMarkdownFences(String text) {
    final trimmed = text.trim();
    // Match ```json ... ``` or ``` ... ```
    final fencePattern = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final match = fencePattern.firstMatch(trimmed);
    return match != null ? match.group(1)! : trimmed;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Riverpod provider for [ReceiptPipelineService].
final receiptPipelineProvider = Provider<ReceiptPipelineService>((ref) {
  return ReceiptPipelineService(
    ref.watch(receiptOcrEngineProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(pendingRepositoryProvider),
  );
});
