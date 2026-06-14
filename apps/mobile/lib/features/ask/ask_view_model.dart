import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/chat_service.dart';
import '../../ai/gemma_service.dart';
import '../../domain/models/ui_models.dart' show ChartData;

/// A single chat message in the Ask conversation.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.isUser,
    this.text = '',
    this.thinking = false,
    this.streaming = false,
    this.chart,
  });

  final bool isUser;
  final String text;

  /// The "thinking" three-dot placeholder is shown (Carson only).
  final bool thinking;

  /// Tokens are still streaming in (drives the blinking caret).
  final bool streaming;

  /// Structured spending chart to render under this message, if the model ran
  /// `chartSpending` during this turn. Null when there is no chart.
  final ChartData? chart;

  bool get hasChart => chart != null;

  ChatMessage copyWith({
    bool? isUser,
    String? text,
    bool? thinking,
    bool? streaming,
    ChartData? chart,
  }) {
    return ChatMessage(
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      thinking: thinking ?? this.thinking,
      streaming: streaming ?? this.streaming,
      chart: chart ?? this.chart,
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

/// Drives the streaming butler conversation against the real on-device chat.
///
/// Flow: [ChatService.start] once, then [ChatService.send] yields a stream of
/// [ChatEvent]s — [TextChunk]s are appended to the in-flight Carson message;
/// a [ChartReady] event attaches its [ChartData] to that message so the screen
/// can render a real chart.
///
/// When the Gemma model is not [GemmaState.ready], or `send` errors, no answer
/// is fabricated: an honest "AI unavailable" message is shown instead.
class AskViewModel extends AutoDisposeNotifier<AskState> {
  StreamSubscription<ChatEvent>? _sendSub;
  bool _chatStarted = false;

  /// Honest message shown when the on-device model cannot answer. Never a
  /// fabricated spending figure — the butler simply declines.
  @visibleForTesting
  static const unavailableMessage =
      'I am afraid I cannot consult your records just now, sir — the model is '
      'still being prepared. Do try again once I am ready.';

  @override
  AskState build() {
    ref.onDispose(() {
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
    _sendSub?.cancel();
    _sendSub = null;
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
      // Model not ready — be honest rather than inventing an answer.
      _failWith(unavailableMessage);
    }
  }

  // --- real path ------------------------------------------------------------

  Future<void> _realReply(String query) async {
    final chat = ref.read(chatServiceProvider);
    try {
      if (!_chatStarted) {
        await chat.start();
        _chatStarted = true;
      }

      var first = true;
      _sendSub = chat.send(query).listen(
        (event) {
          switch (event) {
            case TextChunk(:final text):
              _appendToken(text, isFirst: first);
              first = false;
            case ChartReady(:final chart):
              _attachChart(chart);
          }
        },
        onError: (_) => _failWith(unavailableMessage),
        onDone: () {
          _finishStreaming();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _failWith(unavailableMessage);
    }
  }

  /// Appends a streamed [token] to the last (Carson) message.
  void _appendToken(String token, {required bool isFirst}) {
    final messages = List<ChatMessage>.from(state.messages);
    final i = messages.length - 1;
    if (i < 0 || messages[i].isUser) return;
    if (isFirst) {
      messages[i] =
          messages[i].copyWith(thinking: false, streaming: true, text: token);
    } else {
      messages[i] = messages[i].copyWith(text: messages[i].text + token);
    }
    state = state.copyWith(messages: messages);
  }

  /// Attaches [chart] to the last (Carson) message, clearing the thinking dots
  /// if the chart arrived before any text.
  void _attachChart(ChartData chart) {
    final messages = List<ChatMessage>.from(state.messages);
    final i = messages.length - 1;
    if (i < 0 || messages[i].isUser) return;
    messages[i] = messages[i].copyWith(thinking: false, chart: chart);
    state = state.copyWith(messages: messages);
  }

  /// Marks the in-flight reply complete (stops the caret + streaming flag).
  void _finishStreaming() {
    final messages = List<ChatMessage>.from(state.messages);
    final i = messages.length - 1;
    if (i >= 0 && !messages[i].isUser) {
      messages[i] = messages[i].copyWith(thinking: false, streaming: false);
    }
    state = state.copyWith(messages: messages, streaming: false);
  }

  /// Replaces the in-flight Carson bubble with an honest failure [message] and
  /// ends the turn. No spending figures are fabricated.
  void _failWith(String message) {
    _sendSub?.cancel();
    _sendSub = null;
    final messages = List<ChatMessage>.from(state.messages);
    final i = messages.length - 1;
    if (i >= 0 && !messages[i].isUser) {
      messages[i] = messages[i].copyWith(
        thinking: false,
        streaming: false,
        text: message,
      );
    }
    state = state.copyWith(messages: messages, streaming: false);
  }
}

/// Provider for [AskViewModel].
final askViewModelProvider =
    AutoDisposeNotifierProvider<AskViewModel, AskState>(AskViewModel.new);
