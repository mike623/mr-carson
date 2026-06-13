import 'dart:async';
import 'dart:convert';

import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../domain/models/ai_models.dart';
import 'gemma_service.dart';
import 'prompts.dart';
import '../data/providers.dart' show appDatabaseProvider;

// ---------------------------------------------------------------------------
// Tool-calling path: MANUAL (not native function-calling).
//
// flutter_gemma v0.9.0 does NOT expose a function-calling / Tool API. Its
// `InferenceChat` (lib/core/chat.dart) only offers addQueryChunk(Message),
// generateChatResponse(), and the streaming generateChatResponseAsync(); the
// `Message` type (lib/core/message.dart) is plain text + optional image, with
// no tool-call / tool-result variants. There is therefore no native hook to
// register `queryExpenses` / `topMerchants` as model-callable functions.
//
// So this service implements the documented manual single-step tool loop:
//   1. The system persona (kChatSystemPersona) plus a tool protocol preamble
//      instruct the model to EITHER answer directly OR emit a single first
//      line `TOOL: <name> {json-args}`.
//   2. send() runs a first (buffered) generation, detects that prefix, runs
//      the query against the DB, feeds the JSON result back, and then streams
//      the model's final natural-language answer to the UI.
// The LLM never writes SQL — it only produces QueryExpensesArgs-shaped JSON;
// AppDatabase compiles the parameterized query.
// ---------------------------------------------------------------------------

/// Prefix the model emits on the first line when it wants to call a tool.
const String _kToolPrefix = 'TOOL:';

/// Tool protocol preamble appended to [kChatSystemPersona] when the chat is
/// seeded. Teaches the manual single-step calling convention.
const String _kToolProtocol = '''

## Tool protocol

You have access to local tools that read the user's expense database. You do
NOT write SQL — you only emit a tool name and JSON arguments.

When a question needs data, your reply MUST be exactly one line, nothing else:

TOOL: queryExpenses {"category":"Dining","dateRange":"thisMonth"}

or:

TOOL: topMerchants {"dateRange":"thisMonth","topN":5}

Rules for tool calls:
- The line must start with `TOOL:` followed by the tool name, then a single
  JSON object of arguments. No prose before or after it.
- Tools available: `queryExpenses` and `topMerchants`.
- Argument keys follow the queryExpenses shape: category, merchant, itemName,
  itemNames (array), dateRange, startDate, endDate, limit, includeImages.
  `topMerchants` also accepts `topN`.
- dateRange must be one of: today, yesterday, thisWeek, lastWeek, thisMonth,
  lastMonth, thisYear, allTime.
- Emit only ONE tool call per turn. After I run it I will hand you the JSON
  result and ask you to answer the user.

If the question does NOT need data, just answer the user directly in plain
sentences (no TOOL: line).''';

/// On-device butler chat ("Mr. Carson") backed by Gemma 3n.
///
/// Manages a single [InferenceChat] for the conversation and runs a manual
/// single-step tool loop so the model can read the local expense database
/// before narrating an answer. See the file header for why the loop is manual
/// rather than native function-calling.
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

  // --- lifecycle ------------------------------------------------------------

  /// Creates the chat and seeds it with [kChatSystemPersona] plus the tool
  /// protocol as the first system turn.
  ///
  /// If a chat is already open (e.g. after a stream error left one behind),
  /// it is closed before the new one is created, preventing session leaks.
  /// Throws [StateError] if the Gemma model is not loaded.
  Future<void> start() async {
    // Close any previously open session before replacing it.
    final existing = _chat;
    if (existing != null) {
      _chat = null;
      await existing.session.close();
    }

    final chat = await _gemma.createChat();
    await chat.addQueryChunk(
      Message.text(
        text: '$kChatSystemPersona$_kToolProtocol',
        isUser: false,
      ),
    );
    _chat = chat;
  }

  /// Streams the assistant's reply tokens for [userMessage].
  ///
  /// Runs the manual single-step tool loop:
  /// - Streams the first generation token-by-token, buffering only enough to
  ///   detect a leading `TOOL:` line.
  /// - If the reply is a direct answer, buffered tokens are yielded first and
  ///   subsequent tokens are streamed live — the UI sees progressive output.
  /// - If the reply is a tool call, the full first response is accumulated
  ///   (it should be a single short line), the tool is executed, and the
  ///   second generation is streamed live.
  /// - If the second generation also begins with `TOOL:` (runaway model), a
  ///   fallback apology is yielded instead of leaking the raw prefix.
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

    // ---- first pass: stream tokens, buffer until we know if it's a tool call

    final firstBuffer = StringBuffer();
    bool? isToolCall; // null = not yet decided
    final pendingChunks = <String>[];

    await for (final chunk in chat.generateChatResponseAsync()) {
      firstBuffer.write(chunk);
      final soFar = firstBuffer.toString();

      if (isToolCall == null) {
        // Decision point: once we have enough text to check the prefix.
        if (soFar.trimLeft().length >= _kToolPrefix.length ||
            soFar.contains('\n')) {
          isToolCall = soFar.trimLeft().startsWith(_kToolPrefix);
          if (!isToolCall) {
            // Direct answer — flush buffered chunks and switch to live mode.
            pendingChunks.add(chunk);
            for (final c in pendingChunks) {
              yield c;
            }
            pendingChunks.clear();
            isToolCall = false; // mark decided
            continue;
          }
          // Tool call path — keep accumulating (don't yield anything yet).
          isToolCall = true;
        } else {
          // Not enough text yet — hold the chunk.
          pendingChunks.add(chunk);
        }
      } else if (!isToolCall) {
        // Already decided: direct answer, stream live.
        yield chunk;
      }
      // isToolCall == true: keep accumulating silently.
    }

    // If we never saw enough text to decide, treat it as a direct answer.
    if (isToolCall == null || isToolCall == false) {
      // Flush any still-pending chunks (e.g. very short response).
      for (final c in pendingChunks) {
        yield c;
      }
      return;
    }

    // ---- tool call path: parse + execute ------------------------------------

    final firstResponse = firstBuffer.toString();
    final toolCall = _parseToolCall(firstResponse);

    if (toolCall == null) {
      // Malformed TOOL: line — yield as plain text.
      yield firstResponse;
      return;
    }

    final resultJson = await _runTool(toolCall.name, toolCall.rawArgs);
    await chat.addQueryChunk(
      Message.text(
        text: 'Tool `${toolCall.name}` result (JSON): $resultJson\n'
            'Here are the results, answer the user in plain sentences.',
        isUser: true,
      ),
    );

    // ---- second pass: stream live, guard against runaway tool loop ----------

    int toolCallsInSecondPass = 0;
    final secondBuffer = StringBuffer();
    bool secondIsToolCall = false;
    bool secondDecided = false;

    await for (final chunk in chat.generateChatResponseAsync()) {
      secondBuffer.write(chunk);

      if (!secondDecided) {
        final soFar = secondBuffer.toString();
        if (soFar.trimLeft().length >= _kToolPrefix.length ||
            soFar.contains('\n')) {
          secondIsToolCall = soFar.trimLeft().startsWith(_kToolPrefix);
          secondDecided = true;
          if (secondIsToolCall) {
            toolCallsInSecondPass++;
            break; // stop — we will emit a fallback below
          }
          // Flush the buffer then go live.
          yield soFar;
          continue;
        }
        // Not enough to decide yet — hold.
      } else if (!secondIsToolCall) {
        yield chunk;
      }
    }

    if (toolCallsInSecondPass > 0) {
      // Model tried to make a second tool call — guard: return a safe fallback.
      yield "I'm sorry, I wasn't able to look that up right now. Please try again.";
      return;
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

  // --- tool loop internals --------------------------------------------------

  /// Parses a leading `TOOL: <name> {json}` line, or returns null if [response]
  /// is a direct answer.
  _ToolCall? _parseToolCall(String response) {
    final trimmed = response.trim();
    if (!trimmed.startsWith(_kToolPrefix)) return null;

    final afterPrefix = trimmed.substring(_kToolPrefix.length).trim();
    // Split tool name from the JSON args (args begin at the first '{').
    final braceIdx = afterPrefix.indexOf('{');
    if (braceIdx < 0) {
      // Name but no args — treat args as empty object.
      return _ToolCall(name: afterPrefix.split(RegExp(r'\s')).first, rawArgs: '{}');
    }
    final name = afterPrefix.substring(0, braceIdx).trim();
    final rawArgs = afterPrefix.substring(braceIdx).trim();
    if (name.isEmpty) return null;
    return _ToolCall(name: name, rawArgs: rawArgs);
  }

  /// Executes [name] with [rawArgs], returning a compact JSON result string.
  ///
  /// Never throws: parse/execution failures are returned as an error JSON
  /// object so the model can recover and respond gracefully.
  Future<String> _runTool(String name, String rawArgs) async {
    try {
      final argsMap = _coerceArgsMap(rawArgs);
      final args = QueryExpensesArgs.fromJson(_normalizeArgs(argsMap));

      switch (name) {
        case 'queryExpenses':
          final result = await _db.queryExpenses(args);
          return jsonEncode(result.toJson());
        case 'topMerchants':
          final topN = _readTopN(argsMap);
          final merchants = await _db.topMerchants(args, topN: topN);
          return jsonEncode({
            'merchants': merchants
                .map((m) => {
                      'merchant': m.merchant,
                      'total': m.total,
                      'currency': m.currency,
                    })
                .toList(),
          });
        // TODO: chartSpending tool (needs fl_chart render) — separate task
        default:
          return jsonEncode({'error': 'unknown tool: $name'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  /// Tolerates args arriving as a JSON string or an already-decoded map.
  Map<String, dynamic> _coerceArgsMap(Object? rawArgs) {
    if (rawArgs is Map<String, dynamic>) return rawArgs;
    if (rawArgs is Map) return rawArgs.cast<String, dynamic>();
    if (rawArgs is String) {
      final trimmed = rawArgs.trim();
      if (trimmed.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    throw FormatException('tool args are not a JSON object: $rawArgs');
  }

  /// Normalizes model-supplied args into the exact shape
  /// [QueryExpensesArgs.fromJson] expects.
  ///
  /// Currently this only coerces `dateRange` (the model tends to emit
  /// snake_case like `this_month`) into the camelCase enum name the generated
  /// decoder expects (`thisMonth`). Unknown values are dropped so an odd
  /// dateRange never aborts the whole call.
  Map<String, dynamic> _normalizeArgs(Map<String, dynamic> args) {
    final out = Map<String, dynamic>.from(args);
    final dr = out['dateRange'];
    if (dr is String) {
      final coerced = _coerceDateRange(dr);
      if (coerced == null) {
        out.remove('dateRange'); // Unknown range → omit → query runs unfiltered (all-time).
      } else {
        out['dateRange'] = coerced;
      }
    }
    return out;
  }

  /// Maps a loose dateRange string (snake_case, kebab-case, or already
  /// camelCase) to a valid [DateRange] enum name, or null if unrecognized.
  String? _coerceDateRange(String raw) {
    // Collapse to lowercase alphanumerics for tolerant matching.
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
}

/// A parsed manual tool call: tool [name] plus its raw JSON argument string.
class _ToolCall {
  const _ToolCall({required this.name, required this.rawArgs});

  final String name;
  final String rawArgs;
}

/// Riverpod provider for [ChatService], wired from [gemmaServiceProvider] and
/// [appDatabaseProvider].
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(
    ref.watch(gemmaServiceProvider),
    ref.watch(appDatabaseProvider),
  );
});
