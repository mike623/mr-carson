import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error_reporter.dart';
import '../data/db/app_database.dart';
import '../data/providers.dart';
import '../data/repositories/pending_repository.dart';
import '../domain/models/ai_models.dart';
import 'gemma_service.dart';
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
  ReceiptPipelineService(this._gemma, this._db, this._pending);

  final GemmaService _gemma;
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

      final session = await _gemma.createVisionSession();
      String rawResponse;
      try {
        await session.addQueryChunk(
          Message.withImage(
            text: prompt,
            imageBytes: imageBytes,
            isUser: true,
          ),
        );
        rawResponse = await session.getResponse();
      } finally {
        await session.close();
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
    );
    await _pending.setStatus(pendingId, PendingStatus.inserted);
    return id;
  }

  /// Marks a pending receipt as rejected by the user.
  Future<void> reject(String pendingId) async {
    await _pending.setStatus(pendingId, PendingStatus.rejected);
  }

  // --- helpers --------------------------------------------------------------

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
  @visibleForTesting
  static Map<String, dynamic> coerceDraftJson(
    Map<String, dynamic> d,
    String today,
  ) {
    String str(Object? v, String fallback) =>
        (v is String && v.trim().isNotEmpty) ? v.trim() : fallback;
    double num_(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

    final cur = str(d['currency'], kDefaultCurrency).toUpperCase();
    final rawItems = d['items'] is List ? d['items'] as List : const [];
    final items = rawItems.whereType<Map>().map((it) {
      return {
        'name': str(it['name'], 'Item'),
        'amount': num_(it['amount']),
        'category': str(it['category'], 'Other'),
      };
    }).toList();

    return {
      'merchant': str(d['merchant'], 'Unknown merchant'),
      'date': str(d['date'], today),
      // DB enforces a 3-char currency; fall back if the model returns junk.
      'currency': cur.length == 3 ? cur : kDefaultCurrency,
      'total': num_(d['total']),
      'vat': d['vat'] is num ? (d['vat'] as num).toDouble() : null,
      'items': items,
    };
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
    ref.watch(gemmaServiceProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(pendingRepositoryProvider),
  );
});
