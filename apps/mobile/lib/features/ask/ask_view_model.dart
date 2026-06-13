import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/chat_service.dart';
import '../../ai/gemma_service.dart';

/// A single chat message in the Ask conversation.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.isUser,
    this.text = '',
    this.thinking = false,
    this.streaming = false,
    this.hasChart = false,
  });

  final bool isUser;
  final String text;

  /// The "thinking" three-dot placeholder is shown (Carson only).
  final bool thinking;

  /// Tokens are still streaming in (drives the blinking caret).
  final bool streaming;

  /// Attach the spending chart card under this message.
  final bool hasChart;

  ChatMessage copyWith({
    bool? isUser,
    String? text,
    bool? thinking,
    bool? streaming,
    bool? hasChart,
  }) {
    return ChatMessage(
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      thinking: thinking ?? this.thinking,
      streaming: streaming ?? this.streaming,
      hasChart: hasChart ?? this.hasChart,
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
/// Real path: [ChatService.start] once, then [ChatService.send] yields a token
/// stream that is appended to the in-flight Carson message.
///
/// Fallback: when the Gemma model is not [GemmaState.ready] (offline demo) or
/// `send` throws, the original canned butler reply is streamed word-by-word
/// with the same timing, and the spending chart is attached for spending-type
/// questions — so the prototype behaviour is preserved exactly.
class AskViewModel extends AutoDisposeNotifier<AskState> {
  Timer? _thinkTimer;
  Timer? _streamTimer;
  StreamSubscription<String>? _sendSub;
  bool _chatStarted = false;

  // Canned replies — butler-voiced (verbatim from the prototype).
  static const _replies = [
    "Quite so, sir. You have spent £1,284.60 this month — "
        "dining leads the field, as ever. Shall I break it down further?",
    "Indeed. Your largest single outgoing this period was £148.00 at "
        "Petersham Nurseries on the 7th — a household matter, I believe.",
  ];
  int _replyIndex = 0;

  @override
  AskState build() {
    ref.onDispose(() {
      _thinkTimer?.cancel();
      _streamTimer?.cancel();
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
    _streamTimer?.cancel();
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
      _mockReply(query);
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
        (token) {
          final messages = List<ChatMessage>.from(state.messages);
          final i = messages.length - 1;
          if (i < 0 || messages[i].isUser) return;
          if (first) {
            messages[i] = messages[i]
                .copyWith(thinking: false, streaming: true, text: token);
            first = false;
          } else {
            messages[i] =
                messages[i].copyWith(text: messages[i].text + token);
          }
          state = state.copyWith(messages: messages);
        },
        onError: (_) => _mockReply(query),
        onDone: () {
          final messages = List<ChatMessage>.from(state.messages);
          final i = messages.length - 1;
          if (i >= 0 && !messages[i].isUser) {
            messages[i] = messages[i].copyWith(
              thinking: false,
              streaming: false,
              hasChart: _shouldShowChart(query),
            );
          }
          state = state.copyWith(messages: messages, streaming: false);
        },
        cancelOnError: true,
      );
    } catch (_) {
      _mockReply(query);
    }
  }

  // --- fallback (mock) path -------------------------------------------------

  void _mockReply(String query) {
    _thinkTimer?.cancel();
    _streamTimer?.cancel();

    _thinkTimer = Timer(const Duration(milliseconds: 700), () {
      final reply = _replies[_replyIndex % _replies.length];
      _replyIndex++;
      final words = reply.split(' ');
      int wordIndex = 0;
      final showChart = _shouldShowChart(query);

      // Switch the bubble from thinking → streaming.
      _updateLastCarson((m) => m.copyWith(thinking: false, streaming: true));

      _streamTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
        if (wordIndex < words.length) {
          final addition = (wordIndex == 0 ? '' : ' ') + words[wordIndex];
          _updateLastCarson((m) => m.copyWith(text: m.text + addition));
          wordIndex++;
        } else {
          t.cancel();
          _updateLastCarson(
            (m) => m.copyWith(streaming: false, hasChart: showChart),
          );
          state = state.copyWith(streaming: false);
        }
      });
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

  bool _shouldShowChart(String query) {
    final q = query.toLowerCase();
    return q.contains('spent') ||
        q.contains('month') ||
        q.contains('go') ||
        q.contains('compare');
  }
}

/// Provider for [AskViewModel].
final askViewModelProvider =
    AutoDisposeNotifierProvider<AskViewModel, AskState>(AskViewModel.new);
