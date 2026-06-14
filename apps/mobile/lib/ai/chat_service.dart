import 'dart:async';

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
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/providers.dart' show appDatabaseProvider;
import '../domain/models/ai_models.dart';
import '../domain/models/ui_models.dart' show ChartData;
import 'gemma_service.dart';
import 'prompts.dart';

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

// ---------------------------------------------------------------------------
// Streamed turn events
//
// A turn produces a stream of [ChatEvent]s rather than bare text. Text tokens
// arrive as [TextChunk] (preserving live streaming); when the model invokes the
// `chartSpending` tool we ALSO surface the structured [ChartData] to the UI as a
// [ChartReady] event — without altering the JSON tool-response fed back to the
// model. This is the side-channel that lets the Ask view-model render a real
// fl_chart while the butler narrates the trend in words.
// ---------------------------------------------------------------------------

/// One event in a streamed assistant turn ([ChatService.send]).
@immutable
sealed class ChatEvent {
  const ChatEvent();
}

/// A chunk of assistant text to append to the in-flight reply.
@immutable
class TextChunk extends ChatEvent {
  const TextChunk(this.text);

  final String text;
}

/// Structured spending-chart data, emitted when the model runs `chartSpending`.
///
/// Carries the same buckets that were handed to the model as a tool-response, so
/// the UI can render a real chart while the model narrates the trend.
@immutable
class ChartReady extends ChatEvent {
  const ChartReady(this.chart);

  final ChartData chart;
}

/// Abstraction over the on-device butler chat so the Ask view-model can be
/// driven by a fake in tests (no real Gemma model required).
abstract class ChatService {
  /// Creates + seeds the underlying chat. Call once before [send].
  Future<void> start();

  /// Streams the assistant's reply for [userMessage] as [ChatEvent]s.
  Stream<ChatEvent> send(String userMessage);

  /// Releases the underlying inference session. Safe to call multiple times.
  Future<void> dispose();
}

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
class GemmaChatService implements ChatService {
  /// Creates a chat service over [gemma] (inference) and [db] (expense reads).
  GemmaChatService(this._gemma, this._db);

  final GemmaService _gemma;
  final AppDatabase _db;

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
  ];

  // --- lifecycle ------------------------------------------------------------

  /// Creates the chat (with native tools) and seeds it with
  /// [kChatSystemPersona] as the first turn.
  ///
  /// If a chat is already open (e.g. after a stream error left one behind),
  /// it is closed before the new one is created, preventing session leaks.
  /// Throws [StateError] if the Gemma model is not loaded.
  @override
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
    _chat = chat;
  }

  /// Streams the assistant's reply for [userMessage] as [ChatEvent]s.
  ///
  /// Runs a bounded agent loop over the native sealed [ModelResponse] union:
  /// - [TextResponse] tokens are streamed straight to the UI as [TextChunk]s.
  /// - [FunctionCallResponse] / [ParallelFunctionCallResponse] are executed
  ///   against the local DB, the results are fed back via
  ///   [Message.toolResponse], and the loop re-generates. When a `chartSpending`
  ///   call runs, its structured buckets are additionally surfaced to the UI as
  ///   a [ChartReady] event (the JSON tool-response to the model is unchanged).
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
  @override
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

      await for (final ModelResponse response
          in chat.generateChatResponseAsync()) {
        switch (response) {
          case TextResponse(:final token):
            if (token.isNotEmpty) {
              yieldedText = true;
              yield TextChunk(token);
            }
          case FunctionCallResponse():
            pendingCalls.add(response);
          case ParallelFunctionCallResponse(:final calls):
            pendingCalls.addAll(calls);
          case ThinkingResponse():
            // Internal reasoning — never surface to the UI.
            break;
        }
      }

      if (pendingCalls.isEmpty) {
        // Pure text turn (or empty) — the answer is complete.
        return;
      }

      // Execute every requested tool and feed the results back, then loop to
      // let the model narrate (or call another tool). For `chartSpending`, also
      // surface the typed [ChartData] to the UI before re-generating.
      for (final call in pendingCalls) {
        final outcome = await _runTool(call.name, call.args);
        await chat.addQueryChunk(
          Message.toolResponse(toolName: call.name, response: outcome.response),
        );
        final chart = outcome.chart;
        if (chart != null) {
          yield ChartReady(chart);
        }
      }
    }

    // Turn budget exhausted. If we already streamed some text, leave it as the
    // answer; otherwise emit an honest fallback rather than going silent.
    if (!yieldedText) {
      yield const TextChunk(_kAgentFallback);
    }
  }

  /// Closes the underlying inference session and clears the chat handle.
  ///
  /// Safe to call multiple times.
  @override
  Future<void> dispose() async {
    final chat = _chat;
    _chat = null;
    if (chat != null) {
      await chat.session.close();
    }
  }

  // --- tool execution -------------------------------------------------------

  /// Executes [name] with native-supplied [args].
  ///
  /// Returns a record of:
  /// - `response`: the JSON-serializable map fed back to the model via
  ///   [Message.toolResponse] (model-facing — shape is unchanged from before).
  /// - `chart`: for `chartSpending`, the typed [ChartData] to surface to the UI
  ///   as a [ChartReady] event; `null` for every other tool.
  ///
  /// Never throws: parse/execution failures are returned as an `{'error': ...}`
  /// map (and `chart: null`) so the model can recover and respond gracefully.
  ///
  /// Every returned map embeds `'_tool': name` for disambiguation. The Gemma 4
  /// SDK async path does NOT push a preceding `Message.toolCall` into history,
  /// so for parallel calls the model can otherwise mis-attribute which result
  /// belongs to which tool. Tagging the result with its originating tool name
  /// lets the model line results up with the calls it requested.
  Future<({Map<String, dynamic> response, ChartData? chart})> _runTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final argsMap = _coerceArgsMap(args);
      final queryArgs = QueryExpensesArgs.fromJson(_normalizeArgs(argsMap));

      switch (name) {
        case 'queryExpenses':
          final result = await _db.queryExpenses(queryArgs);
          return (response: {'_tool': name, ...result.toJson()}, chart: null);
        case 'topMerchants':
          final topN = _readTopN(argsMap);
          final merchants = await _db.topMerchants(queryArgs, topN: topN);
          return (
            response: {
              '_tool': name,
              'merchants': merchants
                  .map((m) => {
                        'merchant': m.merchant,
                        'total': m.total,
                        'currency': m.currency,
                      })
                  .toList(),
            },
            chart: null,
          );
        case 'chartSpending':
          final granularity = _readGranularity(argsMap);
          final chart = await _db.byCategoryOverTime(
            queryArgs,
            granularity: granularity,
          );
          // Model-facing JSON (unchanged) …
          final response = {
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
          };
          // … plus the typed payload the UI renders as a real chart.
          return (
            response: response,
            chart: ChartData(
              buckets: chart.rows,
              granularity: chart.granularity,
              currency: chart.currency,
            ),
          );
        default:
          return (
            response: {'_tool': name, 'error': 'unknown tool: $name'},
            chart: null,
          );
      }
    } catch (e) {
      return (response: {'_tool': name, 'error': e.toString()}, chart: null);
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
}

/// Riverpod provider for [ChatService], wired from [gemmaServiceProvider] and
/// [appDatabaseProvider].
final chatServiceProvider = Provider<ChatService>((ref) {
  return GemmaChatService(
    ref.watch(gemmaServiceProvider),
    ref.watch(appDatabaseProvider),
  );
});
