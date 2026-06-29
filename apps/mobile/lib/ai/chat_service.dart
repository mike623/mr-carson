import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/flutter_gemma.dart'
    show
        FunctionCallResponse,
        InferenceChat,
        Message,
        ModelResponse,
        ParallelFunctionCallResponse,
        TextResponse,
        ThinkingResponse,
        Tool,
        ToolChoice;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/providers.dart' show appDatabaseProvider, pendingRepositoryProvider;
import '../data/repositories/expense_repository.dart' show ChartData;
import '../data/repositories/pending_repository.dart';
import '../domain/models/ai_models.dart';
import 'gemma_service.dart';
import 'prompts.dart';

// ---------------------------------------------------------------------------
// Streamed events
//
// `send` no longer yields bare text tokens — it yields a small sealed
// [ChatEvent] union so a single stream can carry BOTH the narrated text AND
// any structured chart produced by the `chartSpending` tool. The UI streams
// [TextDelta] tokens straight into the bubble and, when a [ChartReady] arrives,
// attaches the real chart card under that message.
//
// This is the seam that closes the core gap: previously the chartSpending
// buckets were consumed internally by the agent loop and never surfaced to the
// caller, so the UI had no way to render a real chart.
// ---------------------------------------------------------------------------

/// One event emitted by [ChatService.send].
sealed class ChatEvent {
  const ChatEvent();
}

/// A streamed chunk of the assistant's narrated reply.
class TextDelta extends ChatEvent {
  const TextDelta(this.token);

  final String token;
}

/// A chart the model produced by calling `chartSpending`. Carries the same
/// [ChartData] shape that [ExpenseRepository.categorySpending] returns, so the
/// tool result and the UI payload line up exactly.
class ChartReady extends ChatEvent {
  const ChartReady(this.chart);

  final ChartData chart;
}

/// A draft the model produced via `addExpense` that needs the user's review
/// (low-confidence extraction). Carries the id of the `awaitingConfirmation`
/// pending row so the UI can open the Confirm screen prefilled.
class DraftReady extends ChatEvent {
  const DraftReady(this.pendingId);

  final String pendingId;
}

/// A chunk of the model's internal reasoning ("thinking"). Surfaced so the UI
/// can show it when the user opts in; otherwise the caller simply ignores it.
class ThinkingDelta extends ChatEvent {
  const ThinkingDelta(this.token);

  final String token;
}

/// One ledger lookup (tool call) the model made for this reply: the tool [name]
/// and the [args] it supplied. Surfaced so the UI can show Carson's "workings"
/// when the user opts in. Emitted both for natively-parsed function calls AND
/// for calls the model leaks into its text as a JSON envelope (see
/// [ToolCallEnvelopeFilter]).
class ToolCallStarted extends ChatEvent {
  const ToolCallStarted(this.name, this.args);

  final String name;
  final Map<String, dynamic> args;
}

/// Result of executing one tool: the [response] map fed back to the model, plus
/// (only for `chartSpending`) the [chart] payload surfaced to the UI.
class _ToolOutcome {
  const _ToolOutcome(this.response, {this.chart, this.draftPendingId});

  final Map<String, dynamic> response;
  final ChartData? chart;

  /// Set only by `addExpense` on the low-confidence branch — the id of the
  /// pending row the UI should open for review.
  final String? draftPendingId;
}

// ---------------------------------------------------------------------------
// Tool-calling path: NATIVE function calling (flutter_gemma 0.16.5).
//
// Gemma 4 E2B (.litertlm) emits structured `<|tool_call>...<tool_call|>` tokens
// which the SDK parses into a sealed `ModelResponse` union. We register three
// `Tool`s (queryExpenses, topMerchants, chartSpending) at chat-creation time;
// the model decides when to call them. We run a bounded agent loop: each turn
// either streams a final TextResponse to the UI, or surfaces a
// FunctionCallResponse / ParallelFunctionCallResponse which we execute against
// the local drift DB and feed back via Message.toolResponse, then re-generate.
//
// The LLM never writes SQL — it only produces QueryExpensesArgs-shaped args;
// AppDatabase compiles the parameterized query. This replaces the old manual
// `TOOL:` text-protocol parser entirely (native FC needs no text protocol).
// ---------------------------------------------------------------------------

/// Maximum number of agent turns (generate → maybe tool-call → generate …)
/// before we give up and emit a fallback. Prevents a runaway tool loop.
const int _kMaxAgentTurns = 5;

/// Fallback shown if the agent loop exhausts its turn budget with no answer.
const String _kAgentFallback =
    "I'm sorry, I wasn't able to look that up right now. Please try again.";

/// On-device butler chat ("Mr. Carson") backed by Gemma 4 E2B.
///
/// Manages a single [InferenceChat] (with native function-calling tools) for
/// the conversation and runs a bounded agent loop so the model can read the
/// local expense database before narrating an answer.
///
/// Lifecycle:
/// 1. [start] — create + seed the chat with the butler persona.
/// 2. [send] — stream the assistant's reply for one user message.
/// 3. [dispose] — close the underlying inference session.
class ChatService {
  /// Creates a chat service over [gemma] (inference), [db] (expense reads/
  /// writes) and [pending] (draft confirmation rows for low-confidence adds).
  ChatService(this._gemma, this._db, this._pending);

  final GemmaService _gemma;
  final AppDatabase _db;
  final PendingRepository _pending;

  InferenceChat? _chat;

  /// Native tool declarations exposed to Gemma 4. Descriptions are kept tight
  /// because they are rendered into the prompt and consume context.
  late final List<Tool> _tools = [
    Tool(
      name: 'queryExpenses',
      description:
          'Look up the user\'s expenses. Filter by category, merchant, item '
          'name(s), or date range. Returns matching rows plus totals.',
      parameters: _queryExpensesSchema(),
    ),
    Tool(
      name: 'topMerchants',
      description:
          'Rank the merchants the user spent the most at over a date range. '
          'Returns each merchant with its total.',
      parameters: _topMerchantsSchema(),
    ),
    Tool(
      name: 'chartSpending',
      description:
          'Break spending down by category over time (day/week/month buckets) '
          'for a date range. Use for trend, breakdown, or "over time" questions. '
          'Returns the buckets so you can describe the trend in words.',
      parameters: _chartSpendingSchema(),
    ),
    Tool(
      name: 'addExpense',
      description:
          "Record a NEW expense the user states in plain language (e.g. \"I "
          "spent £12 on lunch at Wagamama yesterday\", \"add £4 coffee\", "
          "\"log groceries 30 quid at Tesco\"). Provide merchant, total, and a "
          'category from the allowed list. Never invent an amount.',
      parameters: _addExpenseSchema(),
    ),
  ];

  // --- lifecycle ------------------------------------------------------------

  /// Creates the chat (with native tools) and seeds it with
  /// [kChatSystemPersona] as the first turn.
  ///
  /// If a chat is already open (e.g. after a stream error left one behind),
  /// it is closed before the new one is created, preventing session leaks.
  /// Throws [StateError] if the Gemma model is not loaded.
  Future<void> start() async {
    final existing = _chat;
    if (existing != null) {
      _chat = null;
      await existing.session.close();
    }

    final chat = await _gemma.createChat(
      tools: _tools,
      supportsFunctionCalls: true,
      toolChoice: ToolChoice.auto,
    );
    await chat.addQueryChunk(
      Message.text(text: kChatSystemPersona, isUser: false),
    );
    await chat.addQueryChunk(
      Message.text(text: "Today's date is ${_todayIso()}.", isUser: false),
    );
    _chat = chat;
  }

  /// Streams the assistant's reply tokens for [userMessage].
  ///
  /// Runs a bounded agent loop over the native sealed [ModelResponse] union:
  /// - [TextResponse] tokens are streamed straight to the UI.
  /// - [FunctionCallResponse] / [ParallelFunctionCallResponse] are executed
  ///   against the local DB, the results are fed back via
  ///   [Message.toolResponse], and the loop re-generates.
  /// - [ThinkingResponse] is ignored (never surfaced to the UI).
  ///
  /// The loop ends when a turn produces only text (no tool call). If the turn
  /// budget ([_kMaxAgentTurns]) is exhausted without a final text answer, a
  /// single honest fallback sentence is yielded.
  ///
  /// On stream error the service is left in an unusable state; callers should
  /// call [dispose] (or [start] — which closes the old session) to recover.
  ///
  /// Throws [StateError] if [start] has not been called.
  Stream<ChatEvent> send(String userMessage) async* {
    final chat = _chat;
    if (chat == null) {
      throw StateError('ChatService.send called before start().');
    }

    await chat.addQueryChunk(Message.text(text: userMessage, isUser: true));

    bool yieldedText = false;

    for (var turn = 0; turn < _kMaxAgentTurns; turn++) {
      // Collect any function calls this turn produced; stream text live.
      final pendingCalls = <FunctionCallResponse>[];

      // Some models (Gemma 4 E2B included) intermittently emit their tool call
      // as a `{"role":"assistant","tool_calls":[…]}` JSON envelope in the TEXT
      // stream instead of as a parsed FunctionCallResponse. The filter strips
      // that leading envelope from the displayed answer and surfaces the calls
      // it carried as [ToolCallStarted] events. Reset per turn.
      final textFilter = ToolCallEnvelopeFilter();

      await for (final ModelResponse response
          in chat.generateChatResponseAsync()) {
        switch (response) {
          case TextResponse(:final token):
            if (token.isNotEmpty) {
              for (final event in textFilter.add(token)) {
                if (event is TextDelta) yieldedText = true;
                yield event;
              }
            }
          case FunctionCallResponse():
            pendingCalls.add(response);
          case ParallelFunctionCallResponse(:final calls):
            pendingCalls.addAll(calls);
          case ThinkingResponse(:final content):
            // Internal reasoning — surfaced for opt-in display only.
            if (content.isNotEmpty) yield ThinkingDelta(content);
        }
      }

      // Flush anything the filter held back waiting on a (never-completed)
      // envelope — emit it as plain text rather than swallowing it.
      for (final event in textFilter.flush()) {
        if (event is TextDelta) yieldedText = true;
        yield event;
      }

      if (pendingCalls.isEmpty) {
        // Pure text turn (or empty) — the answer is complete.
        return;
      }

      // Execute every requested tool and feed the results back, then loop to
      // let the model narrate (or call another tool). When a tool produced a
      // chart, surface its [ChartData] to the caller so the UI can render it.
      for (final call in pendingCalls) {
        yield ToolCallStarted(call.name, call.args);
        final outcome = await _runTool(call.name, call.args);
        await chat.addQueryChunk(
          Message.toolResponse(toolName: call.name, response: outcome.response),
        );
        if (outcome.chart != null) {
          yield ChartReady(outcome.chart!);
        }
        if (outcome.draftPendingId != null) {
          yield DraftReady(outcome.draftPendingId!);
        }
      }
    }

    // Turn budget exhausted. If we already streamed some text, leave it as the
    // answer; otherwise emit an honest fallback rather than going silent.
    if (!yieldedText) {
      yield const TextDelta(_kAgentFallback);
    }
  }

  /// Closes the underlying inference session and clears the chat handle.
  ///
  /// Safe to call multiple times.
  Future<void> dispose() async {
    final chat = _chat;
    _chat = null;
    if (chat != null) {
      await chat.session.close();
    }
  }

  // --- tool execution -------------------------------------------------------

  /// Executes [name] with native-supplied [args], returning a [_ToolOutcome]
  /// whose `response` is the JSON-serializable map fed back to the model via
  /// [Message.toolResponse], plus (for `chartSpending`) the [ChartData] the UI
  /// renders.
  ///
  /// Never throws: parse/execution failures are returned as an `{'error': ...}`
  /// map so the model can recover and respond gracefully.
  ///
  /// Every returned map embeds `'_tool': name` for disambiguation. The Gemma 4
  /// SDK async path does NOT push a preceding `Message.toolCall` into history,
  /// so for parallel calls the model can otherwise mis-attribute which result
  /// belongs to which tool. Tagging the result with its originating tool name
  /// lets the model line results up with the calls it requested.
  Future<_ToolOutcome> _runTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final argsMap = _coerceArgsMap(args);
      final queryArgs = QueryExpensesArgs.fromJson(_normalizeArgs(argsMap));

      switch (name) {
        case 'queryExpenses':
          final result = await _db.queryExpenses(queryArgs);
          return _ToolOutcome({'_tool': name, ...result.toJson()});
        case 'topMerchants':
          final topN = _readTopN(argsMap);
          final merchants = await _db.topMerchants(queryArgs, topN: topN);
          return _ToolOutcome({
            '_tool': name,
            'merchants': merchants
                .map((m) => {
                      'merchant': m.merchant,
                      'total': m.total,
                      'currency': m.currency,
                    })
                .toList(),
          });
        case 'chartSpending':
          final granularity = _readGranularity(argsMap);
          final chart = await _db.byCategoryOverTime(
            queryArgs,
            granularity: granularity,
          );
          return _ToolOutcome(
            {
              '_tool': name,
              'granularity': chart.granularity.name,
              'currency': chart.currency,
              'buckets': chart.rows
                  .map((b) => {
                        'bucket': b.bucket,
                        'category': b.category,
                        'total': b.total,
                      })
                  .toList(),
            },
            // Same record shape ExpenseRepository.categorySpending returns —
            // the tool result and the UI chart payload line up exactly.
            chart: chart,
          );
        case 'addExpense':
          return _runAddExpense(args);
        default:
          return _ToolOutcome({'_tool': name, 'error': 'unknown tool: $name'});
      }
    } catch (e) {
      return _ToolOutcome({'_tool': name, 'error': e.toString()});
    }
  }

  // --- arg coercion (tolerant of loose model output) ------------------------

  /// Tolerates args arriving as an already-decoded map (native FC) or a nested
  /// map type, normalizing to `Map<String, dynamic>`.
  Map<String, dynamic> _coerceArgsMap(Object? rawArgs) {
    if (rawArgs is Map<String, dynamic>) return rawArgs;
    if (rawArgs is Map) return rawArgs.cast<String, dynamic>();
    if (rawArgs == null) return <String, dynamic>{};
    throw FormatException('tool args are not a JSON object: $rawArgs');
  }

  /// Normalizes model-supplied args into the exact shape
  /// [QueryExpensesArgs.fromJson] expects.
  ///
  /// Coerces `dateRange` (the model tends to emit snake_case like `this_month`)
  /// into the camelCase enum name the generated decoder expects (`thisMonth`).
  /// Unknown values are dropped so an odd dateRange never aborts the call. Keys
  /// not understood by [QueryExpensesArgs] (e.g. `topN`, `granularity`) are
  /// stripped here so the generated decoder doesn't choke on them.
  ///
  /// Also defends against loose scalar types from the model: `QueryExpensesArgs.
  /// fromJson` casts `limit` as `num?` and `startDate`/`endDate` as `String?`,
  /// which THROW if the model emits e.g. `limit: "200"` or `startDate: 20240101`.
  /// We coerce those to the expected runtime types (and drop unparseable values)
  /// so the decoder never throws on loose output.
  Map<String, dynamic> _normalizeArgs(Map<String, dynamic> args) {
    final out = Map<String, dynamic>.from(args);
    out.remove('topN');
    out.remove('granularity');

    final dr = out['dateRange'];
    if (dr is String) {
      final coerced = _coerceDateRange(dr);
      if (coerced == null) {
        out.remove('dateRange'); // Unknown range → omit → unfiltered (all-time).
      } else {
        out['dateRange'] = coerced;
      }
    }

    // `limit` must decode as a num. Tolerate String / num; drop if unparseable.
    if (out.containsKey('limit')) {
      final limit = _coerceLimit(out['limit']);
      if (limit == null) {
        out.remove('limit');
      } else {
        out['limit'] = limit;
      }
    }

    // `startDate` / `endDate` must decode as a String that looks like a date.
    // Stringify non-strings; drop anything that doesn't look date-shaped.
    for (final key in const ['startDate', 'endDate']) {
      if (!out.containsKey(key)) continue;
      final coerced = _coerceDate(out[key]);
      if (coerced == null) {
        out.remove(key);
      } else {
        out[key] = coerced;
      }
    }

    return out;
  }

  /// Coerces a loose `limit` value to an int (mirrors [_readTopN] tolerance).
  /// Returns null if it can't be parsed, so the caller drops the key.
  int? _coerceLimit(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// Coerces a loose date value to a date-shaped String, or null to drop it.
  /// Accepts anything that stringifies to a `YYYY-MM-DD`-ish form (digits and
  /// separators); rejects clearly non-date junk rather than letting it through.
  String? _coerceDate(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // Must contain at least 4 consecutive digits (a year) and only date-ish
    // characters. Keeps it simple: the goal is "never throw on loose types".
    if (!RegExp(r'\d{4}').hasMatch(s)) return null;
    if (!RegExp(r'^[0-9\-/.: T]+$').hasMatch(s)) return null;
    return s;
  }

  /// Maps a loose dateRange string (snake_case, kebab-case, or already
  /// camelCase) to a valid [DateRange] enum name, or null if unrecognized.
  String? _coerceDateRange(String raw) {
    final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const lookup = <String, String>{
      'today': 'today',
      'yesterday': 'yesterday',
      'thisweek': 'thisWeek',
      'lastweek': 'lastWeek',
      'thismonth': 'thisMonth',
      'lastmonth': 'lastMonth',
      'thisyear': 'thisYear',
      'alltime': 'allTime',
    };
    return lookup[key];
  }

  /// Reads an optional `topN` from raw args, defaulting to 5.
  int _readTopN(Map<String, dynamic> args) {
    final v = args['topN'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 5;
    return 5;
  }

  /// Reads an optional `granularity` from raw args, defaulting to week.
  Granularity _readGranularity(Map<String, dynamic> args) {
    final v = args['granularity'];
    if (v is String) {
      final key = v.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      switch (key) {
        case 'day':
        case 'daily':
          return Granularity.day;
        case 'month':
        case 'monthly':
          return Granularity.month;
        case 'week':
        case 'weekly':
          return Granularity.week;
      }
    }
    return Granularity.week;
  }

  // --- addExpense tool handler ----------------------------------------------

  /// Builds a draft from [args], then routes by completeness: a confident
  /// extraction (merchant present AND total > 0) is inserted directly; an
  /// incomplete one is parked as an `awaitingConfirmation` pending row for the
  /// user to finish on the Confirm screen.
  Future<_ToolOutcome> _runAddExpense(Map<String, dynamic> args) async {
    final draftJson = buildExpenseDraftJson(_coerceArgsMap(args), _todayIso());
    final draft = ExpenseDraft.fromJson(draftJson);

    final confident = draft.merchant.trim().isNotEmpty && draft.total > 0;
    if (confident) {
      await _db.insertExpense(draft);
      return _ToolOutcome({
        '_tool': 'addExpense',
        'saved': true,
        'merchant': draft.merchant,
        'total': draft.total,
        'currency': draft.currency,
        'category': draft.categories?.first ?? 'Other',
      });
    }

    final pendingId = await _pending.create();
    await _pending.setStatus(
      pendingId,
      PendingStatus.awaitingConfirmation,
      extractedJson: jsonEncode(draft.toJson()),
    );
    return _ToolOutcome(
      {'_tool': 'addExpense', 'needsReview': true},
      draftPendingId: pendingId,
    );
  }

  /// Today's date as 'YYYY-MM-DD'.
  String _todayIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Test seam: runs a tool by name and exposes the outcome (response map,
  /// optional chart, optional draft pending id) without needing a live chat
  /// session. Not used in production.
  @visibleForTesting
  Future<({Map<String, dynamic> response, ChartData? chart, String? draftPendingId})>
      runToolDebug(String name, Map<String, dynamic> args) async {
    final o = await _runTool(name, args);
    return (response: o.response, chart: o.chart, draftPendingId: o.draftPendingId);
  }

  // --- JSON-Schema tool parameter definitions -------------------------------

  static const Map<String, dynamic> _dateRangeProp = {
    'type': 'string',
    'description': 'Named relative date range.',
    'enum': [
      'today',
      'yesterday',
      'thisWeek',
      'lastWeek',
      'thisMonth',
      'lastMonth',
      'thisYear',
      'allTime',
    ],
  };

  /// Shared base properties matching [QueryExpensesArgs].
  static Map<String, dynamic> _baseQueryProperties() => {
        'category': {
          'type': 'string',
          'description': 'Expense category, e.g. "Dining", "Groceries".',
        },
        'merchant': {
          'type': 'string',
          'description': 'Merchant name substring, e.g. "wagamama".',
        },
        'itemName': {
          'type': 'string',
          'description': 'Single line-item name substring.',
        },
        'itemNames': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Item-name synonyms ORed together (concept expansion).',
        },
        'dateRange': _dateRangeProp,
        'startDate': {
          'type': 'string',
          'description': 'Inclusive start date, YYYY-MM-DD.',
        },
        'endDate': {
          'type': 'string',
          'description': 'Inclusive end date, YYYY-MM-DD.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Max rows to return (default 200).',
        },
        'includeImages': {
          'type': 'boolean',
          'description':
              'Only true if the user explicitly asks to see the receipt/photo.',
        },
      };

  Map<String, dynamic> _queryExpensesSchema() => {
        'type': 'object',
        'properties': _baseQueryProperties(),
        'required': <String>[],
      };

  Map<String, dynamic> _topMerchantsSchema() => {
        'type': 'object',
        'properties': {
          ..._baseQueryProperties(),
          'topN': {
            'type': 'integer',
            'description': 'How many merchants to return (default 5).',
          },
        },
        'required': <String>[],
      };

  Map<String, dynamic> _chartSpendingSchema() => {
        'type': 'object',
        'properties': {
          'category': {
            'type': 'string',
            'description': 'Optional category filter.',
          },
          'dateRange': _dateRangeProp,
          'startDate': {
            'type': 'string',
            'description': 'Inclusive start date, YYYY-MM-DD.',
          },
          'endDate': {
            'type': 'string',
            'description': 'Inclusive end date, YYYY-MM-DD.',
          },
          'granularity': {
            'type': 'string',
            'description': 'Bucket size for the trend.',
            'enum': ['day', 'week', 'month'],
          },
        },
        'required': <String>[],
      };

  Map<String, dynamic> _addExpenseSchema() => {
        'type': 'object',
        'properties': {
          'merchant': {
            'type': 'string',
            'description': 'Store / vendor name, e.g. "Wagamama".',
          },
          'total': {
            'type': 'number',
            'description': 'Total amount paid.',
          },
          'category': {
            'type': 'string',
            'description': 'Expense category.',
            'enum': kDefaultCategories,
          },
          'date': {
            'type': 'string',
            'description': 'today, yesterday, or YYYY-MM-DD. Defaults to today.',
          },
          'currency': {
            'type': 'string',
            'description': '3-letter ISO code. Defaults to the user default.',
          },
        },
        'required': <String>['merchant', 'total'],
      };

  // --- addExpense draft coercion --------------------------------------------

  /// Builds an [ExpenseDraft]-shaped JSON map from loose `addExpense` tool
  /// [args]. [today] is 'YYYY-MM-DD'. Tolerant of missing/loose fields so the
  /// draft is always parseable; completeness is judged by the caller, not here.
  @visibleForTesting
  static Map<String, dynamic> buildExpenseDraftJson(
    Map<String, dynamic> args,
    String today,
  ) {
    final merchant = _addStr(args['merchant']);
    final total = _addNum(args['total']);
    final category = _addCategory(args['category']);
    final currency = _addCurrency(args['currency']);
    final date = _addDate(args['date'], today);

    final rawItems = args['items'];
    final List<Map<String, dynamic>> items =
        (rawItems is List && rawItems.isNotEmpty)
            ? rawItems.whereType<Map>().map((it) {
                return <String, dynamic>{
                  'name': _addStr(it['name']).isEmpty
                      ? 'Item'
                      : _addStr(it['name']),
                  'amount': _addNum(it['amount']),
                  'category': _addCategory(it['category'] ?? category),
                };
              }).toList()
            : [
                {
                  'name': merchant.isEmpty ? 'Expense' : merchant,
                  'amount': total,
                  'category': category,
                },
              ];

    return {
      'merchant': merchant,
      'date': date,
      'currency': currency,
      'total': total,
      'vat': 0,
      'items': items,
      'categories': [category],
    };
  }

  static String _addStr(Object? v) =>
      (v is String) ? v.trim() : (v == null ? '' : v.toString().trim());

  static double _addNum(Object? v) {
    if (v is num) return v.toDouble();
    final cleaned = '${v ?? ''}'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  /// Returns a category from [kDefaultCategories] (case-insensitive match),
  /// else 'Other'.
  static String _addCategory(Object? v) {
    final raw = _addStr(v);
    for (final c in kDefaultCategories) {
      if (c.toLowerCase() == raw.toLowerCase()) return c;
    }
    return 'Other';
  }

  static String _addCurrency(Object? v) {
    final cur = _addStr(v).toUpperCase();
    return cur.length == 3 ? cur : kDefaultCurrency;
  }

  /// Maps 'today' / 'yesterday' / a 'YYYY-MM-DD' string to an ISO date,
  /// defaulting to [today] for anything else.
  static String _addDate(Object? v, String today) {
    final raw = _addStr(v).toLowerCase();
    if (raw.isEmpty || raw == 'today') return today;
    if (raw == 'yesterday') {
      final t = DateTime.parse(today).subtract(const Duration(days: 1));
      final y = t.year.toString().padLeft(4, '0');
      final m = t.month.toString().padLeft(2, '0');
      final d = t.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    return today;
  }
}

// ---------------------------------------------------------------------------
// Leaked tool-call envelope filter
// ---------------------------------------------------------------------------

/// Strips a leading `{"role":"assistant","tool_calls":[…]}` JSON envelope that
/// some models emit into the TEXT stream (instead of as a parsed function call),
/// and surfaces the tool calls it carried as [ToolCallStarted] events.
///
/// Feed each streamed text chunk through [add]; it returns the [ChatEvent]s to
/// forward (cleaned [TextDelta]s and any extracted [ToolCallStarted]s). Call
/// [flush] once the turn's text stream ends to release anything still buffered.
///
/// Only a *leading* envelope is stripped (these models prepend it before the
/// narrated answer). Once the start of the stream is resolved as "not an
/// envelope", every later chunk passes straight through so the answer keeps
/// streaming token-by-token.
class ToolCallEnvelopeFilter {
  /// Guards against an unbounded buffer if a malformed `{…` never balances.
  static const int _maxBuffer = 8192;

  bool _resolved = false;
  final StringBuffer _buf = StringBuffer();

  /// Processes a streamed text [chunk], returning events to forward now.
  List<ChatEvent> add(String chunk) {
    if (_resolved) return [TextDelta(chunk)];
    _buf.write(chunk);
    return _tryResolve(finalChunk: false);
  }

  /// Releases anything still buffered at end of stream as plain text.
  List<ChatEvent> flush() {
    if (_resolved) return const [];
    return _tryResolve(finalChunk: true);
  }

  List<ChatEvent> _tryResolve({required bool finalChunk}) {
    final raw = _buf.toString();
    final lead = raw.trimLeft();

    // Empty / whitespace-only so far — keep waiting (or drop if final).
    if (lead.isEmpty) {
      if (finalChunk) _resolved = true;
      return const [];
    }

    // Doesn't start with an object → not an envelope. Pass everything through.
    if (!lead.startsWith('{')) {
      _resolved = true;
      return [TextDelta(raw)];
    }

    final start = raw.indexOf('{');
    final end = _matchObjectEnd(raw, start);
    if (end < 0) {
      // Incomplete object so far. Keep buffering unless the stream ended or we
      // blew the cap — then give up and emit verbatim.
      if (finalChunk || raw.length > _maxBuffer) {
        _resolved = true;
        return [TextDelta(raw)];
      }
      return const [];
    }

    _resolved = true;
    final objectText = raw.substring(start, end);
    final remainder = raw.substring(end);

    final calls = _extractToolCalls(objectText);
    if (calls == null) {
      // Parsed-but-not-an-envelope, or unparseable → leave the text untouched.
      return [TextDelta(raw)];
    }

    return [
      ...calls,
      if (remainder.trim().isNotEmpty) TextDelta(remainder),
    ];
  }

  /// Returns the index just past the object starting at [start], or -1 if the
  /// braces don't balance within [s] yet. String contents (and escapes) are
  /// skipped so braces inside quoted values don't throw off the count.
  static int _matchObjectEnd(String s, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return -1;
  }

  /// Parses [objectText] and, if it is a tool-call envelope, returns the calls
  /// as [ToolCallStarted] events. Returns null if it isn't an envelope (so the
  /// caller leaves the text as-is).
  static List<ToolCallStarted>? _extractToolCalls(String objectText) {
    Object? decoded;
    try {
      decoded = jsonDecode(objectText);
    } catch (_) {
      return null;
    }
    if (decoded is! Map || !decoded.containsKey('tool_calls')) return null;

    final out = <ToolCallStarted>[];
    void walk(Object? node) {
      if (node is List) {
        for (final e in node) {
          walk(e);
        }
        return;
      }
      if (node is Map) {
        final fn = node['function'];
        if (fn is Map && fn['name'] is String) {
          out.add(
            ToolCallStarted(
              fn['name'] as String,
              _asArgs(fn['arguments']),
            ),
          );
        }
      }
    }

    walk(decoded['tool_calls']);
    return out;
  }

  /// Coerces a call's `arguments` (a map, or a JSON-encoded string) to a map.
  static Map<String, dynamic> _asArgs(Object? raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return d.cast<String, dynamic>();
      } catch (_) {
        // fall through
      }
    }
    return const <String, dynamic>{};
  }
}

/// Riverpod provider for [ChatService], wired from [gemmaServiceProvider],
/// [appDatabaseProvider], and [pendingRepositoryProvider].
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(
    ref.watch(gemmaServiceProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(pendingRepositoryProvider),
  );
});
