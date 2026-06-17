import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User opt-ins for surfacing Mr. Carson's "workings" in the Ask transcript.
///
/// Both default OFF — the chat shows only his narrated answer. When enabled,
/// the Ask bubble renders his private reasoning and/or the ledger lookups
/// (tool calls) he made, prettily, above the answer.
@immutable
class TranscriptPrefs {
  const TranscriptPrefs({
    this.showThinking = false,
    this.showToolCalls = false,
  });

  /// Show the model's internal reasoning (a collapsible "Reasoning" block).
  final bool showThinking;

  /// Show the ledger lookups (tool calls) the model made for this reply.
  final bool showToolCalls;

  TranscriptPrefs copyWith({bool? showThinking, bool? showToolCalls}) =>
      TranscriptPrefs(
        showThinking: showThinking ?? this.showThinking,
        showToolCalls: showToolCalls ?? this.showToolCalls,
      );
}

/// Holds the transcript opt-ins. In-memory, mirroring [currencyProvider]
/// (the app keeps no persisted settings store).
class TranscriptPrefsNotifier extends Notifier<TranscriptPrefs> {
  @override
  TranscriptPrefs build() => const TranscriptPrefs();

  void setShowThinking(bool v) => state = state.copyWith(showThinking: v);
  void setShowToolCalls(bool v) => state = state.copyWith(showToolCalls: v);
}

final transcriptPrefsProvider =
    NotifierProvider<TranscriptPrefsNotifier, TranscriptPrefs>(
  TranscriptPrefsNotifier.new,
);
