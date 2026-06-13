import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final draft = ExpenseDraft.fromJson(decoded);

      await _pending.setStatus(
        pendingId,
        PendingStatus.awaitingConfirmation,
        rawOcr: rawResponse,
        extractedJson: jsonEncode(draft.toJson()),
      );

      return ReceiptResult.success(pendingId, draft);
    } catch (e) {
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
