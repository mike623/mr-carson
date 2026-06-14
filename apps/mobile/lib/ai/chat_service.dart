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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/providers.dart' show appDatabaseProvider;
import '../domain/models/ai_models.dart';
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
  /// Creates a chat service over [gemma] (inference) and [db] (expense reads).
  ChatService(this._gemma, this._db);

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
  Stream<String> send(String userMessage) async* {
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
              yield token;
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
      // let the model narrate (or call another tool).
      for (final call in pendingCalls) {
        final result = await _runTool(call.name, call.args);
        await chat.addQueryChunk(
          Message.toolResponse(toolName: call.name, response: result),
        );
      }
    }

    // Turn budget exhausted. If we already streamed some text, leave it as the
    // answer; otherwise emit an honest fallback rather than going silent.
    if (!yieldedText) {
      yield _kAgentFallback;
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

  /// Executes [name] with native-supplied [args], returning a JSON-serializable
  /// result map for [Message.toolResponse].
  ///
  /// Never throws: parse/execution failures are returned as an `{'error': ...}`
  /// map so the model can recover and respond gracefully.
  Future<Map<String, dynamic>> _runTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final argsMap = _coerceArgsMap(args);
      final queryArgs = QueryExpensesArgs.fromJson(_normalizeArgs(argsMap));

      switch (name) {
        case 'queryExpenses':
          final result = await _db.queryExpenses(queryArgs);
          return result.toJson();
        case 'topMerchants':
          final topN = _readTopN(argsMap);
          final merchants = await _db.topMerchants(queryArgs, topN: topN);
          return {
            'merchants': merchants
                .map((m) => {
                      'merchant': m.merchant,
                      'total': m.total,
                      'currency': m.currency,
                    })
                .toList(),
          };
        case 'chartSpending':
          final granularity = _readGranularity(argsMap);
          final chart = await _db.byCategoryOverTime(
            queryArgs,
            granularity: granularity,
          );
          return {
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
        default:
          return {'error': 'unknown tool: $name'};
      }
    } catch (e) {
      return {'error': e.toString()};
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
    return out;
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
  return ChatService(
    ref.watch(gemmaServiceProvider),
    ref.watch(appDatabaseProvider),
  );
});
