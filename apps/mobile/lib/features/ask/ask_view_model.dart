import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/chat_service.dart';
import '../../ai/gemma_service.dart';
import '../../ai/model_mode.dart';
import '../../data/repositories/expense_repository.dart' show ChartData;
import '../shell/shell_view_model.dart';

// Sentinel used by [ChatMessage.copyWith] so callers can explicitly clear
// [ChatMessage.chart] to null by passing `chart: null`.
const Object _chartSentinel = Object();

/// One ledger lookup (tool call) Mr. Carson made for a reply — shown in the
/// transcript only when the user opts in (Settings → his workings).
@immutable
class ToolCall {
  const ToolCall({required this.name, this.args = const {}});

  final String name;
  final Map<String, dynamic> args;

  /// A compact one-line rendering of the args, e.g. `dateRange: thisMonth`.
  /// Empty when the call took no arguments.
  String get prettyArgs =>
      args.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
}

/// A single chat message in the Ask conversation.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.isUser,
    this.text = '',
    this.thinking = false,
    this.streaming = false,
    this.chart,
    this.thinkingText = '',
    this.toolCalls = const [],
  });

  final bool isUser;
  final String text;

  /// The "thinking" three-dot placeholder is shown (Carson only).
  final bool thinking;

  /// Tokens are still streaming in (drives the blinking caret).
  final bool streaming;

  /// Structured spending chart produced by the `chartSpending` tool, attached
  /// when the model charted spending for this reply. `null` ⇒ no chart card.
  final ChartData? chart;

  /// The model's accumulated internal reasoning for this reply. Rendered only
  /// when the user opts in; otherwise ignored.
  final String thinkingText;

  /// The ledger lookups (tool calls) the model made for this reply. Rendered
  /// only when the user opts in.
  final List<ToolCall> toolCalls;

  /// Creates a copy with the given fields replaced.
  ///
  /// [chart] uses a sentinel so that `copyWith(chart: null)` explicitly clears
  /// the chart rather than being a no-op. Omitting [chart] preserves the
  /// current value.
  ChatMessage copyWith({
    bool? isUser,
    String? text,
    bool? thinking,
    bool? streaming,
    Object? chart = _chartSentinel,
    String? thinkingText,
    List<ToolCall>? toolCalls,
  }) {
    return ChatMessage(
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      thinking: thinking ?? this.thinking,
      streaming: streaming ?? this.streaming,
      chart: identical(chart, _chartSentinel) ? this.chart : chart as ChartData?,
      thinkingText: thinkingText ?? this.thinkingText,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }
}

/// Immutable state for the Ask screen.
@immutable
class AskState {
  const AskState({
    this.messages = const [],
    this.streaming = false,
  });

  final List<ChatMessage> messages;
  final bool streaming;

  bool get showGreeting => messages.isEmpty;

  AskState copyWith({
    List<ChatMessage>? messages,
    bool? streaming,
  }) {
    return AskState(
      messages: messages ?? this.messages,
      streaming: streaming ?? this.streaming,
    );
  }
}

/// Drives the streaming butler conversation.
///
/// Real path: [ChatService.start] once, then [ChatService.send] yields a stream
/// of [ChatEvent]s — [TextDelta] tokens are appended to the in-flight Carson
/// message; a [ChartReady] attaches the real spending [ChartData] to it.
///
/// When the Gemma model is not [GemmaState.ready] (or `send` throws) there is no
/// honest answer to give, so Carson surfaces a short "AI unavailable" message in
/// his own voice rather than fabricating one.
class AskViewModel extends AutoDisposeNotifier<AskState> {
  Timer? _thinkTimer;
  StreamSubscription<ChatEvent>? _sendSub;
  bool _chatStarted = false;

  /// Honest message shown when the model isn't ready to answer — butler-voiced,
  /// no fabricated figures.
  static const _unavailableReply =
      "Forgive me, sir — I'm not yet ready to answer. Do set me up and "
      "I shall attend to your ledger at once.";

  @override
  AskState build() {
    ref.onDispose(() {
      _thinkTimer?.cancel();
      _sendSub?.cancel();
    });
    return const AskState();
  }

  // --- public commands ------------------------------------------------------

  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.streaming) return;

    final messages = [
      ...state.messages,
      ChatMessage(isUser: true, text: trimmed),
    ];
    state = state.copyWith(messages: messages);
    _beginCarsonReply(trimmed);
  }

  void stop() {
    _thinkTimer?.cancel();
    _sendSub?.cancel();
    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isNotEmpty && !messages.last.isUser) {
      messages[messages.length - 1] = messages.last.copyWith(
        thinking: false,
        streaming: false,
      );
    }
    state = state.copyWith(messages: messages, streaming: false);
  }

  // --- reply orchestration --------------------------------------------------

  void _beginCarsonReply(String query) {
    // Append a thinking Carson bubble.
    final messages = [
      ...state.messages,
      const ChatMessage(isUser: false, thinking: true),
    ];
    state = state.copyWith(messages: messages, streaming: true);

    final gemma = ref.read(gemmaServiceProvider);
    if (gemma.state == GemmaState.ready) {
      _realReply(query);
    } else {
      _unavailable();
    }
  }

  // --- real path ------------------------------------------------------------

  Future<void> _realReply(String query) async {
    final chat = ref.read(chatServiceProvider);
    try {
      if (!_chatStarted) {
        final online = ref.read(resolvedBackendProvider) == Backend.online;
        await chat.start(online: online);
        _chatStarted = true;
      }

      var first = true;
      var gotText = false; // tracks whether any TextDelta arrived this reply
      _sendSub = chat.send(query).listen(
        (event) {
          switch (event) {
            case TextDelta(:final token):
              _appendToken(token, first: first);
              first = false;
              gotText = true;
            case ChartReady(:final chart):
              _updateLastCarson((m) => m.copyWith(chart: chart));
            case ThinkingDelta(:final token):
              _updateLastCarson(
                (m) => m.copyWith(thinkingText: m.thinkingText + token),
              );
            case ToolCallStarted(:final name, :final args):
              _updateLastCarson(
                (m) => m.copyWith(
                  toolCalls: [...m.toolCalls, ToolCall(name: name, args: args)],
                ),
              );
            case DraftReady(:final pendingId):
              ref.read(shellViewModelProvider.notifier).reviewPending(pendingId);
          }
        },
        onError: (_) {
          if (gotText) {
            // Tokens already arrived — finalize gracefully rather than
            // clobbering the partial answer with the unavailable copy.
            _updateLastCarson(
              (m) => m.copyWith(
                thinking: false,
                streaming: false,
                text: '${m.text} — forgive me, I lost my thread, sir.',
              ),
            );
            state = state.copyWith(streaming: false);
          } else {
            // Nothing streamed yet — honest unavailable message is appropriate.
            _unavailable();
          }
        },
        onDone: () {
          final messages = List<ChatMessage>.from(state.messages);
          final i = messages.length - 1;
          if (i >= 0 && !messages[i].isUser) {
            messages[i] = messages[i].copyWith(
              thinking: false,
              streaming: false,
            );
          }
          state = state.copyWith(messages: messages, streaming: false);
        },
        cancelOnError: true,
      );
    } catch (_) {
      _unavailable();
    }
  }

  /// Appends a streamed [token] to the in-flight Carson bubble, flipping it out
  /// of the thinking placeholder on the first token.
  void _appendToken(String token, {required bool first}) {
    final messages = List<ChatMessage>.from(state.messages);
    final i = messages.length - 1;
    if (i < 0 || messages[i].isUser) return;
    if (first) {
      messages[i] =
          messages[i].copyWith(thinking: false, streaming: true, text: token);
    } else {
      messages[i] = messages[i].copyWith(text: messages[i].text + token);
    }
    state = state.copyWith(messages: messages);
  }

  // --- model-unavailable path ----------------------------------------------

  /// Surfaces the honest "AI unavailable" message after a brief think, with no
  /// chart and no fabricated answer.
  void _unavailable() {
    _thinkTimer?.cancel();
    _sendSub?.cancel();

    _thinkTimer = Timer(const Duration(milliseconds: 400), () {
      _updateLastCarson(
        (m) => m.copyWith(
          thinking: false,
          streaming: false,
          text: _unavailableReply,
        ),
      );
      state = state.copyWith(streaming: false);
    });
  }

  /// Applies [update] to the last (Carson) message, if present.
  void _updateLastCarson(ChatMessage Function(ChatMessage) update) {
    final messages = List<ChatMessage>.from(state.messages);
    final i = messages.length - 1;
    if (i < 0 || messages[i].isUser) return;
    messages[i] = update(messages[i]);
    state = state.copyWith(messages: messages);
  }
}

/// Provider for [AskViewModel].
final askViewModelProvider =
    AutoDisposeNotifierProvider<AskViewModel, AskState>(AskViewModel.new);
